//
//  JournalEntry.swift
//  LYFESTYL
//
//  The app/cache representation of a single journal entry plus its structured
//  insights. The CloudKit private database is authoritative; this is what the UI
//  and the local offline cache work with. Record<->domain mapping lives in
//  CloudKitService.
//

import Foundation

/// How the raw text was captured.
nonisolated enum EntrySource: String, Codable, Hashable {
    case text
    case voice

    var symbolName: String {
        switch self {
        case .text:  "keyboard"
        case .voice: "waveform"
        }
    }
}

/// Pipeline state of an entry. The raw text is saved the instant it's created;
/// `status` tracks how far the on-device + sync pipeline has gotten.
nonisolated enum EntryStatus: String, Codable, Hashable {
    case pending     // saved locally, not yet broken down by the model
    case processing  // model is currently running
    case processed   // breakdown complete
    case failed      // model/sync failed; will be retried, raw text is safe
}

/// One organized field captured from the guided flow, in the user's own words.
/// e.g. label "What you're logging", value "A meal". These replace the old
/// AI "insights": the app helps organize, it doesn't judge.
nonisolated struct EntryField: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var value: String

    init(id: UUID = UUID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

nonisolated struct JournalEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID?
    var rawText: String
    var source: EntrySource
    var status: EntryStatus
    var schemaVersion: Int

    /// The single holistic category this entry belongs to (nil = a free thought
    /// with nothing trackable). The whole entry is classed/colored by this.
    var category: InsightCategory?
    /// Optional refinement of the category (e.g. SOCIAL "partner", or a meal type).
    var subtag: String?
    /// Clean, neutral display title (set by the guided flow or behind-the-scenes
    /// classification). Replaces the old judgmental `overallSummary`.
    var title: String?
    /// The user's organized answers from the guided flow.
    var fields: [EntryField]
    /// For ACTIVITY entries: the structured workout (exercises + optional sets).
    /// Nil for every other category and for free-text activity we couldn't parse
    /// into movements. Rides the same pipeline + CloudKit sync as everything else.
    var workout: WorkoutPayload?

    var createdAt: Date
    /// The calendar day the entry belongs to (auto-stamped to "today").
    var entryDate: Date

    /// Local-only: whether the raw record has been pushed to iCloud yet.
    var syncedToCloud: Bool

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        rawText: String,
        source: EntrySource,
        status: EntryStatus = .pending,
        schemaVersion: Int = InsightSchema.version,
        category: InsightCategory? = nil,
        subtag: String? = nil,
        title: String? = nil,
        fields: [EntryField] = [],
        workout: WorkoutPayload? = nil,
        createdAt: Date = Date(),
        entryDate: Date? = nil,
        syncedToCloud: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.rawText = rawText
        self.source = source
        self.status = status
        self.schemaVersion = schemaVersion
        self.category = category
        self.subtag = subtag
        self.title = title
        self.fields = fields
        self.workout = workout
        self.createdAt = createdAt
        self.entryDate = entryDate ?? Calendar.current.startOfDay(for: createdAt)
        self.syncedToCloud = syncedToCloud
    }
}

extension JournalEntry {
    /// A short, human title for the Log list, prefers the clean `title`, then
    /// the trimmed raw text.
    var listTitle: String {
        if let t = title, !t.isEmpty { return t }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled entry" : trimmed
    }
}

/// Schema versioning for the proprietary breakdown (CLAUDE.md §1: "version your
/// schema so future entries stay comparable").
nonisolated enum InsightSchema {
    // v2: added MIND / SOCIAL / WORK categories and the SOCIAL `relationship`
    //     subtag.
    // v3: added the per-category `evidence` reasoning step (quote-then-judge)
    //     to curb over-classification and literal-word misranking on the 3B model.
    // v4: added the persisted user-facing `reasoning` explanation per insight
    //     (powers the expanded category view and Refine flow).
    // v5: dropped ranks, metrics and per-category insights entirely. An entry now
    //     carries ONE holistic `category`, an optional `subtag`, a clean `title`,
    //     and the user's own organized `fields`. The model only classifies and
    //     titles behind the scenes; it never judges.
    // v6: ACTIVITY entries can carry a structured `workout` (exercises + optional
    //     sets/reps/weight), powering the muscle-balance read in STYL. Free-written
    //     workouts are parsed into the same shape on-device.
    static let version = 6
}
