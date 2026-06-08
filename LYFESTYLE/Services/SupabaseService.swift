//
//  SupabaseService.swift
//  LYFESTYL
//
//  All cloud persistence (CLAUDE.md §4.2): Supabase is authoritative. This wraps
//  PostgREST CRUD for `entries` and `insights` and maps between the snake_case
//  database rows (DTOs) and the camelCase domain models.
//
//  Date handling note (verified): the Supabase decoder parses `timestamptz`
//  fine, but a bare Postgres `date` column FAILS to decode into Swift `Date`.
//  So `entry_date` (a `date` column, ideal for SQL grouping) is carried as a
//  "yyyy-MM-dd" String in the DTOs and converted here. `created_at` is
//  `timestamptz` and maps directly to `Date`.
//

import Foundation
import Supabase

struct SupabaseService {
    let client: SupabaseClient

    init?(client: SupabaseClient? = SupabaseConfig.client) {
        guard let client else { return nil }
        self.client = client
    }

    // MARK: - Reads

    /// Fetch all entries (with their insights) for a user, newest first.
    func fetchEntries(userID: UUID) async throws -> [JournalEntry] {
        let rows: [EntryRow] = try await client
            .from("entries")
            .select("*, insights(*)")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    // MARK: - Writes

    /// Insert the raw entry row (called the moment the entry is created, so the
    /// raw text is never lost even if the model breakdown fails later).
    func insertEntryRow(_ entry: JournalEntry, userID: UUID) async throws {
        let row = EntryInsert(entry: entry, userID: userID)
        try await client.from("entries").insert(row).execute()
    }

    /// Update an entry after the on-device breakdown completes.
    func updateEntryProcessed(_ entry: JournalEntry) async throws {
        let payload = EntryUpdate(status: entry.status.rawValue, overall_summary: entry.overallSummary)
        try await client
            .from("entries")
            .update(payload)
            .eq("id", value: entry.id)
            .execute()
    }

    /// Replace the insights for an entry (delete-then-insert keeps re-processing
    /// idempotent).
    func replaceInsights(_ insights: [Insight], entryID: UUID, userID: UUID) async throws {
        try await client.from("insights").delete().eq("entry_id", value: entryID).execute()
        guard !insights.isEmpty else { return }
        let rows = insights.map { InsightInsert(insight: $0, userID: userID) }
        try await client.from("insights").insert(rows).execute()
    }

    func deleteEntry(id: UUID) async throws {
        // insights cascade via FK; deleting the entry is enough.
        try await client.from("entries").delete().eq("id", value: id).execute()
    }

    /// Upsert a minimal profile row (best-effort; ignores failures).
    func upsertProfile(userID: UUID, displayName: String?) async {
        let row = ProfileUpsert(id: userID, display_name: displayName)
        _ = try? await client.from("profiles").upsert(row).execute()
    }
}

// MARK: - Date helpers

enum SupabaseDate {
    /// "yyyy-MM-dd" in UTC, matching a Postgres `date` column.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { dayFormatter.string(from: date) }
    static func date(from string: String) -> Date {
        dayFormatter.date(from: String(string.prefix(10))) ?? Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - DTOs (snake_case database rows)

private struct EntryInsert: Encodable {
    let id: UUID
    let user_id: UUID
    let raw_text: String
    let source: String
    let status: String
    let schema_version: Int
    let overall_summary: String?
    let created_at: Date
    let entry_date: String

    init(entry: JournalEntry, userID: UUID) {
        id = entry.id
        user_id = userID
        raw_text = entry.rawText
        source = entry.source.rawValue
        status = entry.status.rawValue
        schema_version = entry.schemaVersion
        overall_summary = entry.overallSummary
        created_at = entry.createdAt
        entry_date = SupabaseDate.string(from: entry.entryDate)
    }
}

private struct EntryUpdate: Encodable {
    let status: String
    let overall_summary: String?
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let display_name: String?
}

private struct InsightInsert: Encodable {
    let id: UUID
    let entry_id: UUID
    let user_id: UUID
    let category: String
    let rank: String
    let rank_score: Int
    let title: String
    let detail: String
    let calories: Int?
    let protein_grams: Int?
    let carbs_grams: Int?
    let fat_grams: Int?
    let water_ounces: Int?
    let active_minutes: Int?
    let distance_miles: Double?
    let sleep_hours: Double?
    let created_at: Date
    let entry_date: String

    init(insight: Insight, userID: UUID) {
        id = insight.id
        entry_id = insight.entryID
        user_id = userID
        category = insight.category.rawValue
        rank = insight.rank.rawValue
        rank_score = insight.rank.score
        title = insight.title
        detail = insight.detail
        calories = insight.calories
        protein_grams = insight.proteinGrams
        carbs_grams = insight.carbsGrams
        fat_grams = insight.fatGrams
        water_ounces = insight.waterOunces
        active_minutes = insight.activeMinutes
        distance_miles = insight.distanceMiles
        sleep_hours = insight.sleepHours
        created_at = insight.createdAt
        entry_date = SupabaseDate.string(from: insight.entryDate)
    }
}

private struct EntryRow: Decodable {
    let id: UUID
    let user_id: UUID
    let raw_text: String
    let source: String
    let status: String
    let schema_version: Int?
    let overall_summary: String?
    let created_at: Date
    let entry_date: String
    let insights: [InsightRow]?

    func toDomain() -> JournalEntry {
        JournalEntry(
            id: id,
            userID: user_id,
            rawText: raw_text,
            source: EntrySource(rawValue: source) ?? .text,
            status: EntryStatus(rawValue: status) ?? .processed,
            schemaVersion: schema_version ?? InsightSchema.version,
            overallSummary: overall_summary,
            createdAt: created_at,
            entryDate: SupabaseDate.date(from: entry_date),
            insights: (insights ?? []).compactMap { $0.toDomain() },
            syncedToCloud: true
        )
    }
}

private struct InsightRow: Decodable {
    let id: UUID
    let entry_id: UUID
    let category: String
    let rank: String
    let title: String?
    let detail: String?
    let calories: Int?
    let protein_grams: Int?
    let carbs_grams: Int?
    let fat_grams: Int?
    let water_ounces: Int?
    let active_minutes: Int?
    let distance_miles: Double?
    let sleep_hours: Double?
    let created_at: Date
    let entry_date: String

    func toDomain() -> Insight? {
        guard let category = InsightCategory(rawValue: category) else { return nil }
        return Insight(
            id: id,
            entryID: entry_id,
            category: category,
            rank: Rank(modelValue: rank),
            title: title ?? "",
            detail: detail ?? "",
            calories: calories,
            proteinGrams: protein_grams,
            carbsGrams: carbs_grams,
            fatGrams: fat_grams,
            waterOunces: water_ounces,
            activeMinutes: active_minutes,
            distanceMiles: distance_miles,
            sleepHours: sleep_hours,
            createdAt: created_at,
            entryDate: SupabaseDate.date(from: entry_date)
        )
    }
}
