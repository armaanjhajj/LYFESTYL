//
//  JournalStore.swift
//  LYFESTYL
//
//  The data brain. Coordinates the offline-safe pipeline (CLAUDE.md §4 polish):
//    1. save the raw entry locally the instant it's created (never lost)
//    2. push the raw row to Supabase
//    3. run the on-device Foundation Models breakdown
//    4. sync the resulting insights to Supabase
//  Any step can fail (no model, no network) without data loss; failed/pending
//  work is retried on appear, foreground, and when the model becomes available.
//
//  Supabase is authoritative; `entries` here is the live, observable mirror.
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

    /// Tombstones: entries deleted this session, so an in-flight pipeline or a
    /// refresh can't resurrect them.
    private var deletedEntryIDs: Set<UUID> = []

    private let engine: InsightEngine
    private let local = LocalStore()
    private let service = SupabaseService()
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

    /// Create an entry from text or transcribed voice. Saves immediately and
    /// starts the breakdown. Returns the new entry's id.
    @discardableResult
    func addEntry(text: String, source: EntrySource) async -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entry = JournalEntry(
            userID: userID,
            rawText: trimmed,
            source: source,
            status: .pending
        )
        entries.insert(entry, at: 0)
        await persist()

        await process(entryID: entry.id)
        return entry.id
    }

    // MARK: - Pipeline

    /// Run the full pipeline for one entry (idempotent; safe to retry). Each
    /// state change is persisted with an awaited `persist()` so writes can't
    /// interleave or land out of order.
    func process(entryID: UUID) async {
        guard !deletedEntryIDs.contains(entryID) else { return }
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var entry = entries[idx]

        // 1) Ensure the raw row is in the cloud (raw text is never lost). The
        //    on-device breakdown does NOT need the network, so a cloud failure
        //    here must not stop us — we just retry the sync later.
        if !entry.syncedToCloud, let uid = userID, let service {
            do {
                try await service.insertEntryRow(entry, userID: uid)
                entry.syncedToCloud = true
            } catch {
                entry.syncedToCloud = false
            }
            update(entry)
            await persist()
        }

        // 2) Run the on-device breakdown if it hasn't been done yet.
        if entry.status != .processed {
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
                let breakdown = try await engine.breakdown(of: entry.rawText)
                // The user may have deleted the entry while the model ran.
                guard !deletedEntryIDs.contains(entryID) else { return }
                let now = Date()
                let insights = breakdown.categories.compactMap {
                    Insight(from: $0, entryID: entry.id, entryDate: entry.entryDate, createdAt: now)
                }
                entry.insights = insights
                entry.overallSummary = breakdown.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // 3) Sync the finished breakdown to the cloud — only once the raw row is
        //    there, so we never hit a foreign-key violation.
        if entry.status == .processed, entry.syncedToCloud,
           !deletedEntryIDs.contains(entryID), let uid = userID, let service {
            do {
                try await service.replaceInsights(entry.insights, entryID: entry.id, userID: uid)
                try await service.updateEntryProcessed(entry)
            } catch {
                syncError = "Saved on device; couldn't sync the breakdown yet."
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
        guard let uid = userID, let service else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let cloud = try await service.fetchEntries(userID: uid)
            merge(cloud: cloud)
            await persist()
        } catch {
            // Offline or transient — keep showing the cache silently.
        }
    }

    func deleteEntry(_ entry: JournalEntry) async {
        deletedEntryIDs.insert(entry.id)
        entries.removeAll { $0.id == entry.id }
        await persist()
        if let service, entry.syncedToCloud {
            try? await service.deleteEntry(id: entry.id)
        }
    }

    // MARK: - Derived data

    var allInsights: [Insight] { entries.flatMap(\.insights) }

    var hasAnyEntries: Bool { !entries.isEmpty }

    /// Entries grouped by calendar day, newest day first.
    var entriesByDay: [(day: Date, entries: [JournalEntry])] {
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.entryDate) }
        return groups
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

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
