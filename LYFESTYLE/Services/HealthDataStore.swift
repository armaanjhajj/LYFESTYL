//
//  HealthDataStore.swift
//  LYFESTYL
//
//  The brain of the aggregation feature: owns the unified training history, coordinates every
//  connector, runs the analysis, and persists the result.
//
//  MERGE POLICY is the interesting part. The same session can arrive from more than one place:
//  a lifting session recorded on a Garmin watch appears in Apple Health AND, if the user also
//  logged it, in Hevy. Showing it twice would double every volume figure and every load
//  number. So overlapping sessions are collapsed by time window and sport, and the winner is
//  chosen by which source carries the most useful detail for that kind of session, with the
//  loser recorded in `mergedSources` so the UI can still say both saw it.
//
//  SYNC is incremental wherever the source allows it. Hevy exposes a change feed, HealthKit is
//  queried from the last read forward, and FIT imports are keyed by a deterministic identity so
//  re-importing the same file updates rather than duplicates.
//
//  Nothing here blocks the UI: the analysis runs on an actor, and syncs are cancellable.
//

import Foundation
import Observation
import HealthKit

@MainActor
@Observable
final class HealthDataStore {

    // MARK: - State

    private(set) var workouts: [UnifiedWorkout] = []
    private(set) var snapshots: [DailySnapshot] = []
    private(set) var analysis: AnalysisResult?

    /// Insight ids the user has dismissed, so they stay dismissed across recomputation.
    private(set) var dismissedInsightIDs: Set<String> = []

    private(set) var connections: [DataSource: ConnectionState] = [:]
    private(set) var isAnalysing = false
    private(set) var lastAnalysisDuration: TimeInterval?
    private(set) var hasLoadedCache = false

    /// A message worth showing the user about the last operation.
    var statusMessage: String?
    var errorMessage: String?

    // MARK: - Connection state

    nonisolated enum ConnectionState: Equatable, Sendable {
        case notConnected
        case connecting
        case syncing(progress: Double?, detail: String?)
        case connected(lastSync: Date?, itemCount: Int)
        case failed(String)

        var isConnected: Bool {
            switch self {
            case .connected, .syncing: true
            default: false
            }
        }

        var isBusy: Bool {
            switch self {
            case .connecting, .syncing: true
            default: false
            }
        }

        var lastSync: Date? {
            if case .connected(let date, _) = self { return date }
            return nil
        }

        var errorText: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    // MARK: - Dependencies

    private let local = HealthLocalStore()
    private let runner = AnalyticsRunner()
    private let cloud = HealthCloudKitService()
    private let healthStore = HKHealthStore()
    private let profile: AthleteProfile

    private var reader: HealthKitReader { HealthKitReader(store: healthStore) }

    private var templates: HevyTemplateCache = .empty
    private var bookmarks: SyncBookmarks = .empty

    private var analysisTask: Task<Void, Never>?
    private var syncTasks: [DataSource: Task<Void, Never>] = [:]

    let isHealthAvailable: Bool

    init(profile: AthleteProfile) {
        self.profile = profile
        isHealthAvailable = HKHealthStore.isHealthDataAvailable()
        connections[.appleHealth] = isHealthAvailable ? .notConnected : .failed("Health data is not available on this device.")
        connections[.hevy] = KeychainStore.has(.hevyAPIKey) ? .connected(lastSync: nil, itemCount: 0) : .notConnected
        connections[.garmin] = .notConnected
    }

    // MARK: - Lifecycle

    /// Load the cache and kick off an analysis. Fast, and safe to call repeatedly.
    func loadCache() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        async let cachedWorkouts = local.loadWorkouts()
        async let cachedSnapshots = local.loadSnapshots()
        async let cachedTemplates = local.loadTemplates()
        async let cachedBookmarks = local.loadBookmarks()
        async let cachedDismissed = local.loadDismissedInsightIDs()

        workouts = await cachedWorkouts
        snapshots = await cachedSnapshots
        templates = await cachedTemplates
        bookmarks = await cachedBookmarks
        dismissedInsightIDs = await cachedDismissed

        updateConnectionCounts()
        scheduleAnalysis()
    }

    /// Refresh every connected source, then reanalyse.
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            if connections[.appleHealth]?.isConnected == true {
                group.addTask { await self.syncAppleHealth() }
            }
            if KeychainStore.has(.hevyAPIKey) {
                group.addTask { await self.syncHevy() }
            }
        }
        await pushToCloud()
        scheduleAnalysis()
    }

    // MARK: - Apple Health

    /// Ask for HealthKit permission, then do a first read.
    func connectAppleHealth() async {
        guard isHealthAvailable else { return }
        connections[.appleHealth] = .connecting
        do {
            try await reader.requestAuthorization()
            UserDefaults.standard.set(true, forKey: "health_requested_authorization")
            await syncAppleHealth(fullHistory: true)
        } catch {
            // A thrown authorization error means the sheet failed, not that the user declined,
            // which HealthKit deliberately never reveals.
            connections[.appleHealth] = .failed("Could not open Health permissions.")
        }
    }

    /// Read from Apple Health. Incremental unless a full history is requested.
    func syncAppleHealth(fullHistory: Bool = false) async {
        guard isHealthAvailable else { return }
        syncTasks[.appleHealth]?.cancel()

        connections[.appleHealth] = .syncing(progress: nil, detail: "Reading Apple Health")

        let calendar = Calendar.current
        let now = Date()
        // Overlap the previous read by a few days: HealthKit samples can arrive late, and a
        // Garmin watch that has not synced for a while backfills when it does.
        let start: Date
        if fullHistory || bookmarks.healthKitEarliestRead == nil {
            start = calendar.date(byAdding: .day, value: -AnalyticsRunner.historyDays, to: now) ?? now
        } else {
            let lastRead = bookmarks.healthKitLastRead ?? now
            start = calendar.date(byAdding: .day, value: -7, to: lastRead) ?? now
        }

        let reader = self.reader
        async let fetchedWorkouts = reader.workouts(from: start, to: now)
        async let fetchedSnapshots = reader.dailySnapshots(from: start, to: now)
        async let anchors = reader.profileAnchors()

        let newWorkouts = await fetchedWorkouts
        let newSnapshots = await fetchedSnapshots
        let readAnchors = await anchors

        guard !Task.isCancelled else { return }

        merge(workouts: newWorkouts)
        merge(snapshots: newSnapshots)

        profile.learn(
            observedMaxHeartRate: readAnchors.maxHeartRate,
            observedFTP: readAnchors.ftp,
            observedBodyMassKg: readAnchors.bodyMassKg
        )

        bookmarks.healthKitLastRead = now
        if bookmarks.healthKitEarliestRead == nil || fullHistory {
            bookmarks.healthKitEarliestRead = start
        }

        await persist()
        let count = workouts.filter { $0.origin.source == .appleHealth || $0.origin.source == .garmin }.count
        connections[.appleHealth] = .connected(lastSync: now, itemCount: count)
        scheduleAnalysis()
    }

    // MARK: - Hevy

    /// Validate and store a Hevy API key, then backfill.
    func connectHevy(apiKey: String) async -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        connections[.hevy] = .connecting
        let api = HevyAPI(apiKey: trimmed)
        do {
            try await api.validateKey()
        } catch let error as HevyError {
            connections[.hevy] = .failed(error.localizedDescription)
            return false
        } catch {
            connections[.hevy] = .failed(error.localizedDescription)
            return false
        }

        guard KeychainStore.write(trimmed, for: .hevyAPIKey) else {
            connections[.hevy] = .failed("Could not save the key to the keychain.")
            return false
        }
        await syncHevy(fullBackfill: true)
        return true
    }

    func disconnectHevy() async {
        syncTasks[.hevy]?.cancel()
        KeychainStore.delete(.hevyAPIKey)
        // Drop the synced sessions but keep everything else.
        workouts.removeAll { $0.origin.source == .hevy }
        bookmarks.hevyEventsSince = nil
        bookmarks.hevyBackfillCompletedAt = nil
        bookmarks.hevyWorkoutCount = nil
        templates = .empty
        connections[.hevy] = .notConnected
        await persist()
        scheduleAnalysis()
    }

    /// Sync Hevy. Uses the change feed when a backfill has already run.
    func syncHevy(fullBackfill: Bool = false) async {
        guard let key = KeychainStore.read(.hevyAPIKey) else {
            connections[.hevy] = .notConnected
            return
        }
        syncTasks[.hevy]?.cancel()

        let api = HevyAPI(apiKey: key)
        connections[.hevy] = .syncing(progress: nil, detail: "Connecting to Hevy")

        do {
            // Exercise templates carry the muscle attribution, so they come first.
            if templates.isEmpty || templates.isStale {
                connections[.hevy] = .syncing(progress: nil, detail: "Loading exercise catalog")
                templates = try await fetchTemplates(api: api)
            }

            let needsBackfill = fullBackfill || bookmarks.hevyBackfillCompletedAt == nil
            if needsBackfill {
                try await backfillHevy(api: api)
            } else {
                try await incrementalHevy(api: api)
            }

            bookmarks.hevyEventsSince = Date()
            await persist()
            let count = workouts.filter { $0.origin.source == .hevy }.count
            connections[.hevy] = .connected(lastSync: Date(), itemCount: count)
            scheduleAnalysis()
        } catch let error as HevyError {
            if error == .cancelled { return }
            connections[.hevy] = .failed(error.localizedDescription)
        } catch {
            connections[.hevy] = .failed(error.localizedDescription)
        }
    }

    private func fetchTemplates(api: HevyAPI) async throws -> HevyTemplateCache {
        var cache = HevyTemplateCache()
        var page = 1
        var pageCount = 1
        // The template endpoint is the only one allowing 100 per page, so the whole catalog is
        // usually a handful of requests.
        while page <= pageCount, page <= 40 {
            let result = try await api.exerciseTemplates(page: page)
            cache.insert(result.templates)
            pageCount = result.pageCount
            page += 1
            try? await Task.sleep(for: HevyAPI.requestSpacing)
        }
        cache.fetchedAt = Date()
        return cache
    }

    /// Walk the full workout history. Paged at ten per request, which is Hevy's cap.
    private func backfillHevy(api: HevyAPI) async throws {
        let total = try await api.workoutCount()
        bookmarks.hevyWorkoutCount = total

        var page = 1
        var pageCount = 1
        var imported: [UnifiedWorkout] = []

        while page <= pageCount {
            try Task.checkCancellation()
            let result = try await api.workouts(page: page)
            pageCount = result.pageCount

            for dto in result.workouts {
                if let workout = HevyMapper.workout(from: dto, templates: templates) {
                    imported.append(workout)
                }
            }

            let progress = pageCount > 0 ? Double(page) / Double(pageCount) : nil
            connections[.hevy] = .syncing(
                progress: progress,
                detail: "Importing workouts, \(imported.count) of \(total)"
            )
            // Merge as we go so a long backfill shows results rather than a blank screen.
            merge(workouts: imported)
            imported = []

            page += 1
            try? await Task.sleep(for: HevyAPI.requestSpacing)
        }

        // Body measurements, which is where Hevy keeps weight and body fat.
        var measurementPage = 1
        var measurementPages = 1
        var measurements: [HevyBodyMeasurementDTO] = []
        while measurementPage <= measurementPages, measurementPage <= 50 {
            try Task.checkCancellation()
            let result = try await api.bodyMeasurements(page: measurementPage)
            measurements.append(contentsOf: result.measurements)
            measurementPages = result.pageCount
            measurementPage += 1
            try? await Task.sleep(for: HevyAPI.requestSpacing)
        }
        merge(snapshots: HevyMapper.snapshots(from: measurements))

        bookmarks.hevyBackfillCompletedAt = Date()
    }

    /// Apply changes since the last sync, including deletions.
    ///
    /// Hevy exposes no delete endpoint and a deleted workout simply stops appearing in the
    /// list, so the change feed is the ONLY way to learn something was removed.
    private func incrementalHevy(api: HevyAPI) async throws {
        let since = bookmarks.hevyEventsSince ?? Date(timeIntervalSince1970: 0)
        var page = 1
        var pageCount = 1
        var updated: [UnifiedWorkout] = []
        var deletedIDs: Set<String> = []

        while page <= pageCount, page <= 100 {
            try Task.checkCancellation()
            let result = try await api.events(since: since, page: page)
            pageCount = result.pageCount

            for event in result.events {
                switch event {
                case .updated(let dto):
                    if let workout = HevyMapper.workout(from: dto, templates: templates) {
                        updated.append(workout)
                    }
                case .deleted(let id, _):
                    deletedIDs.insert(SourceRef(source: .hevy, foreignID: id).uniqueKey)
                }
            }
            page += 1
            try? await Task.sleep(for: HevyAPI.requestSpacing)
        }

        if !deletedIDs.isEmpty {
            workouts.removeAll { deletedIDs.contains($0.id) }
            for id in deletedIDs { await cloud.deleteWorkout(id: id) }
        }
        if !updated.isEmpty {
            merge(workouts: updated)
        }
    }

    // MARK: - FIT import

    /// Import one or more FIT files the user picked.
    ///
    /// This is the path that gives Garmin sessions their full detail: sample series, GPS,
    /// power, plus the wellness metrics Apple Health never receives.
    func importFITFiles(urls: [URL]) async -> FITImportSummary {
        var summary = FITImportSummary()
        connections[.garmin] = .syncing(progress: 0, detail: "Reading files")

        for (index, url) in urls.enumerated() {
            // Files picked through the document browser are security-scoped.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                summary.failed += 1
                summary.errors.append("\(url.lastPathComponent): could not be read.")
                continue
            }

            do {
                // Decoding a large activity is real work, so it runs off the main actor.
                let result = try await Task.detached(priority: .userInitiated) {
                    try FITImporter.import(data: data, filename: url.lastPathComponent)
                }.value

                merge(workouts: result.workouts)
                merge(snapshots: result.snapshots)

                profile.learn(
                    observedMaxHeartRate: result.observedMaxHeartRate,
                    observedRestingHeartRate: result.observedRestingHeartRate,
                    observedFTP: result.observedFTP,
                    observedBodyMassKg: result.observedBodyMassKg
                )
                if let sex = result.observedSex, profile.sex == .unspecified {
                    profile.sex = sex
                }

                summary.imported += 1
                summary.workoutsAdded += result.workouts.count
                summary.daysAdded += result.snapshots.count
                if result.checksumFailed { summary.checksumWarnings += 1 }
                if result.wasEmpty {
                    summary.errors.append("\(url.lastPathComponent): decoded but contained nothing recognisable.")
                }
            } catch let error as FITError {
                summary.failed += 1
                summary.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            } catch {
                summary.failed += 1
                summary.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }

            connections[.garmin] = .syncing(
                progress: Double(index + 1) / Double(max(1, urls.count)),
                detail: "Imported \(summary.imported) of \(urls.count)"
            )
        }

        await persist()
        let garminCount = workouts.filter { $0.origin.source == .garmin }.count
        connections[.garmin] = garminCount > 0
            ? .connected(lastSync: Date(), itemCount: garminCount)
            : .notConnected
        scheduleAnalysis()
        return summary
    }

    nonisolated struct FITImportSummary: Sendable {
        var imported = 0
        var failed = 0
        var workoutsAdded = 0
        var daysAdded = 0
        var checksumWarnings = 0
        var errors: [String] = []

        var isSuccess: Bool { imported > 0 }

        var message: String {
            if imported == 0 {
                return failed > 0 ? "Could not read those files." : "Nothing was imported."
            }
            var parts = ["Imported \(workoutsAdded) session\(workoutsAdded == 1 ? "" : "s")"]
            if daysAdded > 0 { parts.append("\(daysAdded) day\(daysAdded == 1 ? "" : "s") of wellness") }
            if failed > 0 { parts.append("\(failed) file\(failed == 1 ? "" : "s") failed") }
            return parts.joined(separator: ", ") + "."
        }
    }

    // MARK: - Merging

    /// Fold new sessions into the history, replacing by id and collapsing duplicates that came
    /// from different sources.
    private func merge(workouts incoming: [UnifiedWorkout]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for workout in incoming {
            // Re-syncing the same session replaces it, which is what makes the whole pipeline
            // idempotent.
            byID[workout.id] = workout
        }
        workouts = Self.collapseDuplicates(Array(byID.values)).sorted { $0.start > $1.start }
    }

    /// Fold new daily wellness in, merging field by field rather than replacing the day.
    ///
    /// Field-level merging matters because different sources fill different fields on the same
    /// day: Apple Health has steps and SDNN, Garmin has Body Battery and RMSSD, Hevy has body
    /// weight. Replacing the day would throw away whichever arrived first.
    private func merge(snapshots incoming: [DailySnapshot]) {
        guard !incoming.isEmpty else { return }
        var byDay = Dictionary(snapshots.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        for snapshot in incoming {
            if let existing = byDay[snapshot.date] {
                byDay[snapshot.date] = Self.mergeSnapshot(existing, snapshot)
            } else {
                byDay[snapshot.date] = snapshot
            }
        }
        snapshots = byDay.values.sorted { $0.date < $1.date }
    }

    /// Combine two versions of one day, preferring whichever actually has a value.
    ///
    /// Where both have one, the newer wins for measured values, EXCEPT for sleep, where the
    /// staged version wins because a staged night carries strictly more information than an
    /// unstaged one covering the same hours.
    nonisolated static func mergeSnapshot(_ a: DailySnapshot, _ b: DailySnapshot) -> DailySnapshot {
        var result = a

        func take(_ keyPath: WritableKeyPath<DailySnapshot, Double?>) {
            if let value = b[keyPath: keyPath] { result[keyPath: keyPath] = value }
        }
        take(\.restingHeartRate)
        take(\.heartRateVariabilityMs)
        take(\.respiratoryRate)
        take(\.oxygenSaturationPercent)
        take(\.wristTemperatureDeltaC)
        take(\.walkingHeartRateAverage)
        take(\.heartRateRecoveryOneMinute)
        take(\.breathingDisturbances)
        take(\.steps)
        take(\.activeEnergyKcal)
        take(\.basalEnergyKcal)
        take(\.exerciseMinutes)
        take(\.standHours)
        take(\.flightsClimbed)
        take(\.distanceWalkingRunningMeters)
        take(\.timeInDaylightMinutes)
        take(\.vo2Max)
        take(\.bodyMassKg)
        take(\.bodyFatPercent)
        take(\.leanBodyMassKg)
        take(\.mindfulMinutes)
        take(\.bodyBattery)
        take(\.stressAverage)
        take(\.trainingReadiness)
        take(\.garminHrvRmssdMs)

        // Sleep: prefer a staged night, then the longer one.
        switch (a.sleep, b.sleep) {
        case (nil, let new?):
            result.sleep = new
        case (let old?, let new?):
            if new.isStaged && !old.isStaged {
                result.sleep = new
            } else if new.isStaged == old.isStaged, new.asleepSeconds > old.asleepSeconds {
                result.sleep = new
            }
        default:
            break
        }

        result.contributingSources = Array(Set(a.contributingSources + b.contributingSources))
            .sorted { $0.fieldPriority > $1.fieldPriority }
        return result
    }

    /// Collapse sessions that describe the same real-world workout.
    ///
    /// Two sessions are the same when they overlap substantially in time and are the same broad
    /// family. That happens routinely: a Garmin strength session syncs to Apple Health while the
    /// user also logs it in Hevy, and counting both would double the week's volume and load.
    ///
    /// The winner is chosen by which source is authoritative FOR THAT KIND of session, not by a
    /// global ranking: Hevy owns sets and reps, a FIT import owns anything with a sample series.
    nonisolated static func collapseDuplicates(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        let sorted = workouts.sorted { $0.start < $1.start }
        var result: [UnifiedWorkout] = []

        for workout in sorted {
            // Look back only at recent entries: sessions are sorted, so an overlap can only be
            // with something close by.
            if let index = result.lastIndex(where: { existing in
                overlaps(existing, workout) && existing.family == workout.family
            }) {
                result[index] = preferred(result[index], workout)
            } else {
                result.append(workout)
            }
        }
        return result
    }

    /// Whether two sessions describe the same workout: they must overlap by at least half the
    /// shorter one, and start within fifteen minutes of each other.
    nonisolated static func overlaps(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> Bool {
        guard abs(a.start.timeIntervalSince(b.start)) < 900 else { return false }
        let overlapStart = max(a.start, b.start)
        let overlapEnd = min(a.end, b.end)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }
        let shorter = min(a.elapsedSeconds, b.elapsedSeconds)
        guard shorter > 0 else { return false }
        return overlap / shorter >= 0.5
    }

    /// Pick the richer of two descriptions of the same session, keeping the other's provenance.
    nonisolated static func preferred(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> UnifiedWorkout {
        func score(_ workout: UnifiedWorkout) -> Int {
            var points = 0
            // For lifting, the set-by-set record is what matters and only Hevy or a FIT file
            // has it.
            if workout.strength != nil { points += 100 }
            // A sample series unlocks every within-session analysis.
            if workout.heartRateSeries != nil { points += 60 }
            if workout.powerSeries != nil { points += 30 }
            if workout.route != nil { points += 20 }
            if workout.distanceMeters != nil { points += 10 }
            if workout.averageHeartRate != nil { points += 5 }
            points += workout.origin.source.fieldPriority
            return points
        }

        var winner = score(a) >= score(b) ? a : b
        let loser = score(a) >= score(b) ? b : a

        // Keep the loser's provenance so the UI can say both sources saw this.
        var merged = winner.mergedSources
        if !merged.contains(loser.origin), loser.origin.source != winner.origin.source {
            merged.append(loser.origin)
        }
        winner.mergedSources = merged

        // Fill any gap the winner has from the loser, so nothing measured is thrown away.
        if winner.distanceMeters == nil { winner.distanceMeters = loser.distanceMeters }
        if winner.activeEnergyKcal == nil { winner.activeEnergyKcal = loser.activeEnergyKcal }
        if winner.averageHeartRate == nil { winner.averageHeartRate = loser.averageHeartRate }
        if winner.maxHeartRate == nil { winner.maxHeartRate = loser.maxHeartRate }
        if winner.strength == nil { winner.strength = loser.strength }
        if winner.perceivedEffort == nil { winner.perceivedEffort = loser.perceivedEffort }
        if winner.notes == nil { winner.notes = loser.notes }
        return winner
    }

    // MARK: - Analysis

    /// Recompute in the background, coalescing rapid calls.
    func scheduleAnalysis() {
        analysisTask?.cancel()
        let currentWorkouts = workouts
        let currentSnapshots = snapshots
        let currentProfile = profile.snapshot
        let target = sleepTargetHours

        analysisTask = Task { [weak self] in
            guard let self else { return }
            // A short delay coalesces the burst of calls a multi-source sync produces.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            await MainActor.run { self.isAnalysing = true }

            // Learn what the data reveals, then analyse with the sharpened profile.
            let anchors = await self.runner.observedAnchors(
                workouts: currentWorkouts, snapshots: currentSnapshots
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.profile.learn(
                    observedMaxHeartRate: anchors.maxHeartRate,
                    observedRestingHeartRate: anchors.restingHeartRate,
                    observedThresholdPaceSecPerKm: anchors.thresholdPaceSecPerKm,
                    observedBodyMassKg: anchors.bodyMassKg
                )
            }
            let sharpened = await MainActor.run { self.profile.snapshot }

            let result = await self.runner.run(
                workouts: currentWorkouts,
                snapshots: currentSnapshots,
                profile: sharpened,
                sleepTargetHours: target
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.analysis = result
                self.lastAnalysisDuration = result.duration
                self.isAnalysing = false
            }
            _ = currentProfile
        }
    }

    /// Insights the user has not dismissed.
    var visibleInsights: [HealthInsight] {
        (analysis?.insights ?? []).excluding(ids: dismissedInsightIDs)
    }

    func dismissInsight(_ insight: HealthInsight) {
        dismissedInsightIDs.insert(insight.id)
        Task { await local.saveDismissedInsightIDs(dismissedInsightIDs) }
    }

    func restoreDismissedInsights() {
        dismissedInsightIDs = []
        Task { await local.saveDismissedInsightIDs([]) }
    }

    // MARK: - Preferences

    private let sleepTargetKey = "sleep_target_hours"

    var sleepTargetHours: Double? {
        get { UserDefaults.standard.optionalDouble(sleepTargetKey) }
        set { UserDefaults.standard.setOptionalDouble(newValue, sleepTargetKey); scheduleAnalysis() }
    }

    // MARK: - Persistence

    private func persist() async {
        let currentWorkouts = workouts
        let currentSnapshots = snapshots
        let currentTemplates = templates
        let currentBookmarks = bookmarks
        await local.saveWorkouts(currentWorkouts)
        await local.saveSnapshots(currentSnapshots)
        await local.saveTemplates(currentTemplates)
        await local.saveBookmarks(currentBookmarks)
    }

    /// Push the summary layer to CloudKit so a second device sees the same history.
    ///
    /// Sample series are deliberately NOT synced: they are large, they are only needed for
    /// within-session analysis, and they can always be rebuilt from the original source. The
    /// summary plus the cached derived values is what makes the history useful everywhere.
    func pushToCloud() async {
        guard await cloud.isAvailable() else { return }
        do {
            try await cloud.saveWorkouts(workouts)
            try await cloud.saveSnapshots(snapshots)
        } catch {
            // Cloud sync is a convenience on top of a working local store, so a failure is
            // silent rather than alarming.
        }
    }

    /// Pull anything this device has not seen.
    func pullFromCloud() async {
        guard await cloud.isAvailable() else { return }
        do {
            let cloudWorkouts = try await cloud.fetchWorkouts()
            let cloudSnapshots = try await cloud.fetchSnapshots()
            // Local wins where both exist, because local may still hold sample series that the
            // cloud copy deliberately dropped.
            let existing = Set(workouts.map(\.id))
            merge(workouts: cloudWorkouts.filter { !existing.contains($0.id) })
            merge(snapshots: cloudSnapshots)
            await persist()
            scheduleAnalysis()
        } catch {
            // Offline or not signed in; the local store is unaffected.
        }
    }

    // MARK: - Maintenance

    func disconnectAll() async {
        for task in syncTasks.values { task.cancel() }
        analysisTask?.cancel()
        KeychainStore.deleteAll()
        workouts = []
        snapshots = []
        analysis = nil
        templates = .empty
        bookmarks = .empty
        connections = [.appleHealth: .notConnected, .hevy: .notConnected, .garmin: .notConnected]
        await local.clear()
    }

    private func updateConnectionCounts() {
        let hevyCount = workouts.filter { $0.origin.source == .hevy }.count
        if hevyCount > 0, KeychainStore.has(.hevyAPIKey) {
            connections[.hevy] = .connected(lastSync: bookmarks.hevyEventsSince, itemCount: hevyCount)
        }
        let garminCount = workouts.filter { $0.origin.source == .garmin }.count
        if garminCount > 0 {
            connections[.garmin] = .connected(lastSync: nil, itemCount: garminCount)
        }
        let healthCount = workouts.filter { $0.origin.source == .appleHealth }.count
        if healthCount > 0 || !snapshots.isEmpty {
            connections[.appleHealth] = .connected(
                lastSync: bookmarks.healthKitLastRead, itemCount: healthCount
            )
        }
    }

    // MARK: - Queries the UI needs

    /// Sessions on a given day, newest first.
    func workouts(on day: Date, calendar: Calendar = .current) -> [UnifiedWorkout] {
        let start = calendar.startOfDay(for: day)
        return workouts.filter { $0.day == start }.sorted { $0.start > $1.start }
    }

    func workout(id: String) -> UnifiedWorkout? {
        workouts.first { $0.id == id }
    }

    func snapshot(on day: Date, calendar: Calendar = .current) -> DailySnapshot? {
        let start = calendar.startOfDay(for: day)
        return snapshots.first { $0.date == start }
    }

    var hasAnyData: Bool { !workouts.isEmpty || !snapshots.isEmpty }

    var connectedSourceCount: Int {
        connections.values.filter(\.isConnected).count
    }

    var isSyncing: Bool {
        connections.values.contains(where: \.isBusy)
    }
}
