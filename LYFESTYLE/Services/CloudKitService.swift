//
//  CloudKitService.swift
//  LYFESTYL
//
//  All cloud persistence, now fully first-party Apple: CloudKit's PRIVATE database
//  is authoritative for every entry, fully first-party Apple. The
//  private DB is automatically scoped to the signed-in iCloud account, so there is
//  no user_id filtering, no keys, no external service, nothing leaves Apple.
//
//  One record type, "Entry", keyed by the entry's UUID (its recordName), so a save
//  is a simple idempotent upsert that works for both the raw row and the finished,
//  organized entry. The flexible parts (organized `fields`, the structured
//  `workout`) ride along as JSON blobs on the record.
//
//  Offline-safe by design (CLAUDE.md §4): the local cache stays the instant safety
//  net; this syncs it up to iCloud when the account and network are available.
//

import Foundation
import CloudKit

struct CloudKitService {
    static let recordType = "Entry"

    /// Resolved lazily, never at init. `CKContainer.default()` reads the CloudKit
    /// entitlement and throws (an uncatchable ObjC exception) when it's absent, so
    /// we must not touch it at app launch. It is only reached once a signed-in user
    /// actually syncs, which keeps launch and preview builds safe.
    private var container: CKContainer { .default() }
    private var database: CKDatabase { container.privateCloudDatabase }

    init() {}

    // MARK: - Account

    /// Whether the device has a usable iCloud account for the private DB. Sign-in
    /// (Apple) still gates the app; this reports whether cloud sync can actually
    /// happen right now (calm-degradation: entries are safe locally regardless).
    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: - Reads

    /// Fetch every entry in the user's private DB, newest first. Pages through
    /// cursors so large histories come back whole.
    func fetchEntries() async throws -> [JournalEntry] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var domain: [JournalEntry] = []

        var result = try await database.records(matching: query)
        while true {
            for (_, recordResult) in result.matchResults {
                if let record = try? recordResult.get(), let entry = Self.toDomain(record) {
                    domain.append(entry)
                }
            }
            guard let cursor = result.queryCursor else { break }
            result = try await database.records(continuingMatchFrom: cursor)
        }
        return domain.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Writes

    /// Idempotent upsert of the whole entry. Fetches the existing record first (so
    /// CloudKit's change-tag stays valid) and writes all fields, then saves.
    func saveEntry(_ entry: JournalEntry) async throws {
        let id = CKRecord.ID(recordName: entry.id.uuidString)
        let record: CKRecord
        if let existing = try? await database.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        Self.apply(entry, to: record)
        _ = try await database.save(record)
    }

    func deleteEntry(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        _ = try await database.deleteRecord(withID: recordID)
    }

    // MARK: - Mapping

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func apply(_ entry: JournalEntry, to record: CKRecord) {
        record["rawText"] = entry.rawText as CKRecordValue
        record["source"] = entry.source.rawValue as CKRecordValue
        record["status"] = entry.status.rawValue as CKRecordValue
        record["schemaVersion"] = entry.schemaVersion as CKRecordValue
        record["category"] = entry.category?.rawValue as CKRecordValue?
        record["subtag"] = entry.subtag as CKRecordValue?
        record["title"] = entry.title as CKRecordValue?
        record["createdAt"] = entry.createdAt as CKRecordValue
        record["entryDate"] = entry.entryDate as CKRecordValue
        record["userID"] = entry.userID?.uuidString as CKRecordValue?
        record["fields"] = (try? encoder.encode(entry.fields)) as CKRecordValue?
        record["promotedWorkoutID"] = entry.promotedWorkoutID as CKRecordValue?
        if let workout = entry.workout, let data = try? encoder.encode(workout) {
            record["workout"] = data as CKRecordValue
        } else {
            record["workout"] = nil
        }
    }

    private static func toDomain(_ record: CKRecord) -> JournalEntry? {
        guard
            let id = UUID(uuidString: record.recordID.recordName),
            let rawText = record["rawText"] as? String,
            let sourceRaw = record["source"] as? String,
            let statusRaw = record["status"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }

        let fields: [EntryField] = (record["fields"] as? Data)
            .flatMap { try? decoder.decode([EntryField].self, from: $0) } ?? []
        let workout: WorkoutPayload? = (record["workout"] as? Data)
            .flatMap { try? decoder.decode(WorkoutPayload.self, from: $0) }
        let entryDate = (record["entryDate"] as? Date) ?? Calendar.current.startOfDay(for: createdAt)

        return JournalEntry(
            id: id,
            userID: (record["userID"] as? String).flatMap { UUID(uuidString: $0) },
            rawText: rawText,
            source: EntrySource(rawValue: sourceRaw) ?? .text,
            status: EntryStatus(rawValue: statusRaw) ?? .processed,
            schemaVersion: (record["schemaVersion"] as? Int) ?? InsightSchema.version,
            category: (record["category"] as? String).flatMap { InsightCategory(rawValue: $0) },
            subtag: record["subtag"] as? String,
            title: record["title"] as? String,
            fields: fields,
            workout: workout,
            promotedWorkoutID: record["promotedWorkoutID"] as? String,
            createdAt: createdAt,
            entryDate: entryDate,
            syncedToCloud: true
        )
    }
}
