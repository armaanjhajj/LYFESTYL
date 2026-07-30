//
//  HealthLocalStore.swift
//  LYFESTYL
//
//  On-disk cache for synced training and wellness data, so the app opens instantly and works
//  offline. CloudKit stays authoritative for cross-device truth; this is the local mirror and
//  the safety net.
//
//  Kept as its own actor and its own files, separate from the journal cache, because the
//  shapes and lifetimes differ: journal entries are small and hand-written, whereas a year of
//  synced workouts with sample series is megabytes and is rebuildable from its sources.
//
//  Writes are atomic. A crash partway through must not leave a half-written file that fails
//  to decode on next launch and silently loses a year of history.
//

import Foundation

// MARK: - Sync bookmarks

/// Where each connector got to, so a refresh is incremental rather than a full re-download.
nonisolated struct SyncBookmarks: Codable, Sendable {
    /// High-water mark for Hevy's `/workouts/events?since=` endpoint.
    var hevyEventsSince: Date?
    /// When the Hevy backfill finished walking the full history, so it is only done once.
    var hevyBackfillCompletedAt: Date?
    /// Total workouts Hevy reported, for backfill progress.
    var hevyWorkoutCount: Int?
    /// How far back HealthKit has been read.
    var healthKitEarliestRead: Date?
    var healthKitLastRead: Date?

    init(
        hevyEventsSince: Date? = nil,
        hevyBackfillCompletedAt: Date? = nil,
        hevyWorkoutCount: Int? = nil,
        healthKitEarliestRead: Date? = nil,
        healthKitLastRead: Date? = nil
    ) {
        self.hevyEventsSince = hevyEventsSince
        self.hevyBackfillCompletedAt = hevyBackfillCompletedAt
        self.hevyWorkoutCount = hevyWorkoutCount
        self.healthKitEarliestRead = healthKitEarliestRead
        self.healthKitLastRead = healthKitLastRead
    }

    static let empty = SyncBookmarks()
}

// MARK: - Store

actor HealthLocalStore {

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryName: String = "HealthData") {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    // MARK: Generic read and write

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        // Atomic so an interrupted write cannot corrupt an existing good file.
        try? data.write(to: url(name), options: [.atomic])
    }

    // MARK: Workouts

    func loadWorkouts() -> [UnifiedWorkout] {
        load([UnifiedWorkout].self, from: "workouts") ?? []
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) {
        save(workouts, to: "workouts")
    }

    // MARK: Snapshots

    func loadSnapshots() -> [DailySnapshot] {
        load([DailySnapshot].self, from: "snapshots") ?? []
    }

    func saveSnapshots(_ snapshots: [DailySnapshot]) {
        save(snapshots, to: "snapshots")
    }

    // MARK: Hevy templates

    func loadTemplates() -> HevyTemplateCache {
        load(HevyTemplateCache.self, from: "hevy_templates") ?? .empty
    }

    func saveTemplates(_ cache: HevyTemplateCache) {
        save(cache, to: "hevy_templates")
    }

    // MARK: Bookmarks

    func loadBookmarks() -> SyncBookmarks {
        load(SyncBookmarks.self, from: "bookmarks") ?? .empty
    }

    func saveBookmarks(_ bookmarks: SyncBookmarks) {
        save(bookmarks, to: "bookmarks")
    }

    // MARK: Dismissed insights

    func loadDismissedInsightIDs() -> Set<String> {
        load(Set<String>.self, from: "dismissed_insights") ?? []
    }

    func saveDismissedInsightIDs(_ ids: Set<String>) {
        save(ids, to: "dismissed_insights")
    }

    // MARK: Maintenance

    /// Wipe everything, for disconnecting or signing out.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
