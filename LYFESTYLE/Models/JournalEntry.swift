//
//  JournalEntry.swift
//  LYFESTYL
//
//  The app/cache representation of a single journal entry plus its structured
//  insights. Supabase is authoritative; this is what the UI and the local
//  offline cache work with. Row<->domain mapping lives in SupabaseService.
//

import Foundation

/// How the raw text was captured.
enum EntrySource: String, Codable, Hashable {
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
enum EntryStatus: String, Codable, Hashable {
    case pending     // saved locally, not yet broken down by the model
    case processing  // model is currently running
    case processed   // breakdown complete
    case failed      // model/sync failed; will be retried, raw text is safe
}

struct JournalEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID?
    var rawText: String
    var source: EntrySource
    var status: EntryStatus
    var schemaVersion: Int
    var overallSummary: String?
    var createdAt: Date
    /// The calendar day the entry belongs to (auto-stamped to "today").
    var entryDate: Date
    var insights: [Insight]

    /// Local-only: whether the raw row has been pushed to Supabase yet.
    var syncedToCloud: Bool

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        rawText: String,
        source: EntrySource,
        status: EntryStatus = .pending,
        schemaVersion: Int = InsightSchema.version,
        overallSummary: String? = nil,
        createdAt: Date = Date(),
        entryDate: Date? = nil,
        insights: [Insight] = [],
        syncedToCloud: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.rawText = rawText
        self.source = source
        self.status = status
        self.schemaVersion = schemaVersion
        self.overallSummary = overallSummary
        self.createdAt = createdAt
        self.entryDate = entryDate ?? Calendar.current.startOfDay(for: createdAt)
        self.insights = insights
        self.syncedToCloud = syncedToCloud
    }
}

extension JournalEntry {
    /// Insights in stable category order for display.
    var sortedInsights: [Insight] {
        insights.sorted { $0.category.sortIndex < $1.category.sortIndex }
    }

    /// The distinct categories this entry touched, in display order.
    var categories: [InsightCategory] {
        Array(Set(insights.map(\.category))).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// A short, human title for the Log list — prefers the model's summary,
    /// falls back to the trimmed raw text.
    var listTitle: String {
        if let s = overallSummary, !s.isEmpty { return s }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled entry" : trimmed
    }
}

/// Schema versioning for the proprietary breakdown (CLAUDE.md §1: "version your
/// schema so future entries stay comparable").
enum InsightSchema {
    static let version = 1
}
