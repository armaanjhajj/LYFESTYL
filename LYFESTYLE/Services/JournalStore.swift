//
//  JournalStore.swift
//  LYFESTYL
//
//  The data brain. Coordinates the offline-safe pipeline (CLAUDE.md §4 polish):
//    1. save the raw entry locally the instant it's created (never lost)
//    2. push the raw record to the CloudKit private database
//    3. run the on-device Foundation Models breakdown
//    4. sync the resulting organized entry back to CloudKit
//  Any step can fail (no model, no network) without data loss; failed/pending
//  work is retried on appear, foreground, and when the model becomes available.
//
//  The CloudKit private database is authoritative; `entries` here is the live,
//  observable mirror.
//

import Foundation
import Observation

@MainActor
@Observable
final class JournalStore {

    private(set) var entries: [JournalEntry] = []
    private(set) var isRefreshing = false
    private(set) var isProcessing = false
    var syncError: String?

    /// IDs currently being broken down (drives per-row spinners).
    private(set) var inFlight: Set<UUID> = []

    /// Increments exactly once per successful new-entry save. Drives the save
    /// success haptic so it never fires on delete / refresh / sign-out.
    private(set) var savedTick = 0

    /// Tombstones: entries deleted this session, so an in-flight pipeline or a
    /// refresh can't resurrect them.
    private var deletedEntryIDs: Set<UUID> = []

    private let engine: InsightEngine
    /// The unified training history. A free-written session is promoted into a real workout
    /// there rather than being stored on the entry, so hand-logged and synced sessions are the
    /// same kind of thing and are analysed by the same code. Weak to avoid a retain cycle,
    /// since the health store outlives this one and both are owned by the app.
    weak var healthData: HealthDataStore?
    private let local = LocalStore()
    private let service = CloudKitService()
    private var userID: UUID?
    private var hasLoaded = false

    init(engine: InsightEngine) {
        self.engine = engine
    }

    // MARK: - Session lifecycle

    /// Called when a user signs in. Loads the cache, then refreshes from cloud.
    func configure(userID: UUID) async {
        self.userID = userID
        #if DEBUG
        if SampleData.isPreview {
            if !hasLoaded {
                entries = SampleData.entries()
                hasLoaded = true
            }
            return
        }
        #endif
        if !hasLoaded {
            entries = await local.load().filter { $0.userID == userID || $0.userID == nil }
            hasLoaded = true
        }
        await refresh()
        await retryUnfinished()
    }

    /// Called on sign-out. Clears in-memory + on-disk cache.
    func reset() async {
        userID = nil
        entries = []
        hasLoaded = false
        inFlight = []
        await local.clear()
    }

    // MARK: - Creating entries

    /// Free-write path: the user just typed/spoke. We save immediately and let
    /// the on-device model quietly file it under one category behind the scenes.
    @discardableResult
    func addFreeWrite(text: String, source: EntrySource) async -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entry = JournalEntry(
            userID: userID,
            rawText: trimmed,
            source: source,
            status: .pending
        )
        entries.insert(entry, at: 0)
        savedTick += 1
        await persist()

        await process(entryID: entry.id)
        return entry.id
    }

    /// Guided path: the user already chose the category and answered a couple of
    /// short organizing questions. Nothing needs the model, so this is instant.
    /// `note` is the optional free-text they added; `fields` are their answers.
    @discardableResult
    func addGuidedEntry(
        note: String,
        source: EntrySource,
        category: InsightCategory,
        subtag: String?,
        fields: [EntryField]
    ) async -> UUID? {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFields = fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // An entry needs *something*, either a note or at least one answer.
        guard !trimmedNote.isEmpty || !cleanFields.isEmpty else { return nil }

        let cleanSubtag = subtag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = JournalEntry(
            userID: userID,
            rawText: trimmedNote,
            source: source,
            status: .pending,
            category: category,
            subtag: (cleanSubtag?.isEmpty == false) ? cleanSubtag : nil,
            title: Self.guidedTitle(note: trimmedNote, category: category, fields: cleanFields),
            fields: cleanFields
        )
        entries.insert(entry, at: 0)
        savedTick += 1
        await persist()

        await process(entryID: entry.id)
        return entry.id
    }

    /// Free-written workout path (the ACTIVITY logger's "just write it" mode): save
    /// the note now and let the on-device model derive the movements in the
    /// pipeline (matched to the library), keeping the raw note alongside.
    @discardableResult
    func addActivityNote(text: String, source: EntrySource) async -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entry = JournalEntry(
            userID: userID,
            rawText: trimmed,
            source: source,
            status: .pending,
            category: .activity
        )
        entries.insert(entry, at: 0)
        savedTick += 1
        await persist()

        await process(entryID: entry.id)
        return entry.id
    }

    /// Back-compat shim: a plain text/voice entry is treated as a free write.
    @discardableResult
    func addEntry(text: String, source: EntrySource) async -> UUID? {
        await addFreeWrite(text: text, source: source)
    }

    /// A clean, neutral title for a written activity note: the first line, or a plain fallback.
    /// Structured sessions are named by the training history itself.
    static func activityTitle(note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Workout" }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(60))
    }

    /// A clean, deterministic title for a guided entry, no model needed: prefer
    /// the user's note, else their first answer, else the category name.
    private static func guidedTitle(note: String, category: InsightCategory, fields: [EntryField]) -> String {
        if !note.isEmpty {
            let firstLine = note.split(whereSeparator: \.isNewline).first.map(String.init) ?? note
            return String(firstLine.prefix(60))
        }
        if let first = fields.first?.value.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        return category.label.capitalized
    }

    // MARK: - Pipeline

    /// Run the full pipeline for one entry (idempotent; safe to retry). Each
    /// state change is persisted with an awaited `persist()` so writes can't
    /// interleave or land out of order.
    func process(entryID: UUID) async {
        guard !deletedEntryIDs.contains(entryID) else { return }
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var entry = entries[idx]

        // 1) Ensure the raw row is in iCloud (raw text is never lost). The
        //    on-device work does NOT need the network, so a cloud failure here must
        //    not stop us, we just retry the sync later.
        if !entry.syncedToCloud, userID != nil {
            do {
                try await service.saveEntry(entry)
                entry.syncedToCloud = true
            } catch {
                entry.syncedToCloud = false
            }
            update(entry)
            await persist()
        }

        // 2) Organize the entry if it hasn't been done yet.
        if entry.status != .processed {
            // Free-written ACTIVITY: derive structured movements on-device (matched
            // to the exercise library) and keep the raw note alongside. Needs the
            // model; if it's unavailable we leave it pending and retry later.
            if entry.category == .activity, entry.workout == nil,
               entry.fields.isEmpty, !entry.rawText.isEmpty {
                engine.refreshAvailability()
                guard engine.isAvailable else {
                    if entry.status != .pending {
                        entry.status = .pending
                        update(entry)
                        await persist()
                    }
                    return
                }

                inFlight.insert(entryID)
                isProcessing = true
                entry.status = .processing
                update(entry)
                await persist()
                defer {
                    inFlight.remove(entryID)
                    isProcessing = !inFlight.isEmpty
                }

                do {
                    let unit = healthData?.preferredWeightUnit ?? .lb
                    let exercises = try await engine.parseWorkout(entry.rawText, weightUnit: unit)
                    guard !deletedEntryIDs.contains(entryID) else { return }

                    // Promote the parsed session into the unified history. The entry keeps the
                    // raw words; the workout carries the structure. That way one logged session
                    // shows up exactly once, and it is scored and analysed identically to a
                    // session synced from Hevy or a watch.
                    if !exercises.isEmpty, let healthData {
                        let session = StrengthSession(exercises: exercises)
                        let promoted = await healthData.logManualWorkout(
                            title: entry.title,
                            notes: entry.rawText,
                            start: entry.createdAt,
                            durationSeconds: nil,
                            strength: session
                        )
                        entry.promotedWorkoutID = promoted?.id
                        if (entry.title ?? "").isEmpty {
                            entry.title = promoted?.title
                        }
                    }
                    if (entry.title ?? "").isEmpty {
                        entry.title = Self.activityTitle(note: entry.rawText)
                    }
                    entry.status = .processed
                    update(entry)
                    await persist()
                } catch {
                    entry.status = .failed
                    update(entry)
                    await persist()
                    return // raw note is safe; retryUnfinished() will try again
                }
            }
            // Guided / structured entries are already organized by the user, no
            // model needed, so they finish instantly even when it's unavailable.
            else if entry.category != nil {
                if (entry.title ?? "").isEmpty {
                    entry.title = Self.guidedTitle(note: entry.rawText, category: entry.category!, fields: entry.fields)
                }
                entry.status = .processed
                update(entry)
                await persist()
            } else {
                // Free write: quietly classify behind the scenes.
                engine.refreshAvailability()
                guard engine.isAvailable else {
                    // Leave as pending; retryUnfinished() picks it up later.
                    if entry.status != .pending {
                        entry.status = .pending
                        update(entry)
                        await persist()
                    }
                    return
                }

                inFlight.insert(entryID)
                isProcessing = true
                entry.status = .processing
                update(entry)
                await persist()
                defer {
                    inFlight.remove(entryID)
                    isProcessing = !inFlight.isEmpty
                }

                do {
                    let result = try await engine.classify(entry.rawText)
                    // The user may have deleted the entry while the model ran.
                    guard !deletedEntryIDs.contains(entryID) else { return }
                    entry.category = InsightCategory(modelValue: result.category) // nil for NONE
                    let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    entry.title = title.isEmpty ? nil : title
                    if entry.category == .social,
                       let sub = result.subtag?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !sub.isEmpty {
                        entry.subtag = sub
                    }
                    entry.status = .processed
                    update(entry)
                    await persist()
                } catch {
                    entry.status = .failed
                    update(entry)
                    await persist()
                    return // raw entry is safe; retryUnfinished() will try again
                }
            }
        }

        // 3) Sync the finished entry to iCloud, only once the raw row is there.
        if entry.status == .processed, entry.syncedToCloud,
           !deletedEntryIDs.contains(entryID), userID != nil {
            do {
                try await service.saveEntry(entry)
            } catch {
                syncError = "Saved on device; couldn't sync the entry yet."
            }
        }
    }

    /// Re-run any entries that haven't finished (pending/failed) or never synced.
    func retryUnfinished() async {
        let candidates = entries.filter {
            $0.status == .pending || $0.status == .failed || !$0.syncedToCloud
        }
        guard !candidates.isEmpty else { return }
        for entry in candidates {
            await process(entryID: entry.id)
        }
    }

    // MARK: - Refresh / delete

    func refresh() async {
        guard userID != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let cloud = try await service.fetchEntries()
            merge(cloud: cloud)
            await persist()
        } catch {
            // Offline or transient, keep showing the cache silently.
        }
    }

    func deleteEntry(_ entry: JournalEntry) async {
        deletedEntryIDs.insert(entry.id)
        entries.removeAll { $0.id == entry.id }
        await persist()
        if entry.syncedToCloud {
            try? await service.deleteEntry(id: entry.id)
        }
    }

    // MARK: - Derived data

    var hasAnyEntries: Bool { !entries.isEmpty }

    // MARK: - Helpers

    /// Pure in-memory mutation. Callers persist explicitly (with `await`) so disk
    /// writes stay ordered and never interleave.
    private func update(_ entry: JournalEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
    }

    private func persist() async {
        await local.save(entries)
    }

    /// Merge cloud truth with in-flight local work. Cloud wins for finished
    /// entries; local wins for entries still being created/processed offline.
    private func merge(cloud: [JournalEntry]) {
        var byID: [UUID: JournalEntry] = [:]
        for e in cloud where !deletedEntryIDs.contains(e.id) { byID[e.id] = e }
        for local in entries where (!local.syncedToCloud || local.status != .processed) {
            // Keep our fresher local copy for in-flight items.
            byID[local.id] = local
        }
        entries = byID.values.sorted { $0.createdAt > $1.createdAt }
    }
}
