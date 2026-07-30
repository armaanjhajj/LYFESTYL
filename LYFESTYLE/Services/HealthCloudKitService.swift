//
//  HealthCloudKitService.swift
//  LYFESTYL
//
//  Cross-device sync for the aggregated training history, through CloudKit's private database.
//  First-party Apple, automatically scoped to the signed-in iCloud account, no keys and no
//  external service.
//
//  WHAT IS AND IS NOT SYNCED, and why:
//
//    SYNCED: the workout summary (sport, times, distance, energy, heart rate, power, the
//    cached derived values) and the full strength payload, plus every daily wellness snapshot.
//    This is what makes a second device show the same history and the same analysis.
//
//    NOT SYNCED: the sample series and GPS routes. A year of sessions with series is tens of
//    megabytes, they are only needed for within-session analysis on the device that holds the
//    original, and everything computed FROM them (normalized power, aerobic decoupling) is
//    already cached on the record. Pushing them would spend the user's iCloud quota on data
//    that can always be rebuilt from Apple Health or the original FIT file.
//
//  Records are keyed by the unified id, so a save is an idempotent upsert and a re-sync from
//  any device converges rather than duplicating.
//

import Foundation
import CloudKit

nonisolated struct HealthCloudKitService: Sendable {

    static let workoutRecordType = "UnifiedWorkout"
    static let snapshotRecordType = "DailySnapshot"

    /// Resolved lazily, never at init. `CKContainer.default()` reads the CloudKit entitlement
    /// and raises an uncatchable exception when it is absent, so touching it during app launch
    /// or in a preview would crash.
    private var container: CKContainer { .default() }
    private var database: CKDatabase { container.privateCloudDatabase }

    init() {}

    /// Whether the private database is usable right now.
    func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: - Writes

    /// CloudKit accepts at most 400 operations per batch; 300 leaves headroom.
    private static let batchSize = 300

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        let records = workouts.map(Self.record(for:))
        try await save(records)
    }

    func saveSnapshots(_ snapshots: [DailySnapshot]) async throws {
        let records = snapshots.map(Self.record(for:))
        try await save(records)
    }

    private func save(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }
        for chunk in stride(from: 0, to: records.count, by: Self.batchSize) {
            let slice = Array(records[chunk..<min(chunk + Self.batchSize, records.count)])
            // `.allKeys` because these records are fully rewritten each time, and the server
            // change tag is irrelevant when the client is the only writer of this data.
            _ = try await database.modifyRecords(
                saving: slice,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
        }
    }

    func deleteWorkout(id: String) async {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: id))
        _ = try? await database.deleteRecord(withID: recordID)
    }

    // MARK: - Reads

    func fetchWorkouts() async throws -> [UnifiedWorkout] {
        try await fetchAll(recordType: Self.workoutRecordType).compactMap(Self.workout(from:))
    }

    func fetchSnapshots() async throws -> [DailySnapshot] {
        try await fetchAll(recordType: Self.snapshotRecordType).compactMap(Self.snapshot(from:))
    }

    private func fetchAll(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var result = try await database.records(matching: query)
        while true {
            for (_, outcome) in result.matchResults {
                if let record = try? outcome.get() { records.append(record) }
            }
            guard let cursor = result.queryCursor else { break }
            result = try await database.records(continuingMatchFrom: cursor)
        }
        return records
    }

    // MARK: - Mapping

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// CloudKit record names must be a restricted character set and under 255 bytes. Unified
    /// ids look like `hevy:b459cba5-...`, so the colon is replaced rather than left to fail.
    static func recordName(for id: String) -> String {
        id.replacingOccurrences(of: ":", with: "_")
    }

    static func record(for workout: UnifiedWorkout) -> CKRecord {
        let record = CKRecord(
            recordType: workoutRecordType,
            recordID: CKRecord.ID(recordName: recordName(for: workout.id))
        )
        // The whole summary rides as one JSON blob rather than forty separate fields. That
        // keeps the CloudKit schema stable as the model gains metrics, which matters because
        // adding a field to a deployed CloudKit schema is a manual step in the dashboard.
        var stripped = workout
        stripped.heartRateSeries = nil
        stripped.speedSeries = nil
        stripped.powerSeries = nil
        stripped.cadenceSeries = nil
        stripped.altitudeSeries = nil
        stripped.distanceSeries = nil
        stripped.route = nil

        record["payload"] = (try? encoder.encode(stripped)) as CKRecordValue?
        // A few fields are also written plainly so CloudKit can sort and filter without
        // decoding every blob.
        record["unifiedID"] = workout.id as CKRecordValue
        record["startDate"] = workout.start as CKRecordValue
        record["day"] = workout.day as CKRecordValue
        record["sport"] = workout.sport.rawValue as CKRecordValue
        record["source"] = workout.origin.source.rawValue as CKRecordValue
        return record
    }

    static func workout(from record: CKRecord) -> UnifiedWorkout? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? decoder.decode(UnifiedWorkout.self, from: data)
    }

    static func record(for snapshot: DailySnapshot) -> CKRecord {
        // One record per day, keyed by the day, so re-syncing converges.
        let key = ISO8601DateFormatter.dayFormatter.string(from: snapshot.date)
        let record = CKRecord(
            recordType: snapshotRecordType,
            recordID: CKRecord.ID(recordName: "day_\(key)")
        )
        record["payload"] = (try? encoder.encode(snapshot)) as CKRecordValue?
        record["date"] = snapshot.date as CKRecordValue
        return record
    }

    static func snapshot(from record: CKRecord) -> DailySnapshot? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? decoder.decode(DailySnapshot.self, from: data)
    }
}

nonisolated extension ISO8601DateFormatter {
    /// `YYYY-MM-DD` in UTC, for deterministic per-day record names.
    static let dayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
