//
//  HealthService.swift
//  LYFESTYL
//
//  Apple HealthKit integration (CLAUDE.md §3 of this build). Reads the user's
//  MEASURED health data and exposes it as a `HealthSummary` (today's / most-recent
//  values) plus trailing baselines used by the check-in planner to spot anomalies.
//
//  Everything here is measured, never assumed. An empty store (no Apple Watch, no
//  data, or read access not granted) is a normal, fully-supported state: the
//  summary is simply empty and the rest of the app falls back to the journal
//  inferred picture. We never simulate or backfill data that isn't there.
//
//  All reads use the modern async query descriptors (HKStatisticsCollectionQuery-
//  Descriptor / HKSampleQueryDescriptor), verified against the iOS 26 SDK.
//

import Foundation
import Observation
import HealthKit

@MainActor
@Observable
final class HealthService {

    /// The most-recent / today's measured values, ready for STYL.
    private(set) var summary: HealthSummary = .empty
    /// Trailing-window baselines (per metric) the planner compares against to
    /// notice that something has moved. Empty until there's enough history.
    private(set) var baselines: [HealthMetricKind: Double] = [:]
    /// Whether we've taken the user through the system authorization sheet at least
    /// once (so the UI shows "Connect" vs "Connected"). Persisted across launches.
    private(set) var hasRequestedAuthorization: Bool

    /// HealthKit exists on this device (false on hardware without it).
    let isHealthAvailable: Bool

    private let store = HKHealthStore()
    private let calendar = Calendar.current
    private let requestedKey = "health_requested_authorization"

    init() {
        isHealthAvailable = HKHealthStore.isHealthDataAvailable()
        hasRequestedAuthorization = UserDefaults.standard.bool(forKey: requestedKey)
        if !isHealthAvailable {
            summary = .unavailable
        }
        #if DEBUG
        if SampleData.isPreview {
            summary = SampleData.healthSummary
            baselines = SampleData.healthBaselines
            hasRequestedAuthorization = true
        }
        #endif
    }

    // MARK: - Types we read

    private static let quantityMap: [HealthMetricKind: HKQuantityTypeIdentifier] = [
        .steps:                  .stepCount,
        .activeEnergy:           .activeEnergyBurned,
        .exerciseMinutes:        .appleExerciseTime,
        .walkingRunningDistance: .distanceWalkingRunning,
        .restingHeartRate:       .restingHeartRate,
        .heartRateVariability:   .heartRateVariabilitySDNN,
        .respiratoryRate:        .respiratoryRate,
        .oxygenSaturation:       .oxygenSaturation,
    ]

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let mindfulType = HKCategoryType(.mindfulSession)

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [sleepType, mindfulType]
        for id in Self.quantityMap.values { set.insert(HKQuantityType(id)) }
        return set
    }

    /// Units, per metric (matches the display unit in HealthMetricKind).
    private func unit(for kind: HealthMetricKind) -> HKUnit {
        switch kind {
        case .steps:                  .count()
        case .activeEnergy:           .kilocalorie()
        case .exerciseMinutes:        .minute()
        case .walkingRunningDistance: .mile()
        case .restingHeartRate:       HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability:   .secondUnit(with: .milli)
        case .respiratoryRate:        HKUnit.count().unitDivided(by: .minute())
        case .oxygenSaturation:       .percent()
        case .sleepHours, .mindfulMinutes: .minute()  // handled specially
        }
    }

    private func isCumulative(_ kind: HealthMetricKind) -> Bool {
        switch kind {
        case .steps, .activeEnergy, .exerciseMinutes, .walkingRunningDistance: true
        default: false
        }
    }

    // MARK: - Authorization

    /// Walk the user through the native HealthKit permission sheet, then refresh.
    /// HealthKit deliberately does not reveal read-grant status, so we treat a
    /// non-throwing request as "asked" and let an empty summary be normal.
    func requestAuthorization() async {
        guard isHealthAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            hasRequestedAuthorization = true
            UserDefaults.standard.set(true, forKey: requestedKey)
            await refresh()
        } catch {
            // Authorization failures are non-fatal; the app stays journal-only.
        }
    }

    // MARK: - Refresh

    /// Pull today's / most-recent measured values and the trailing baselines.
    /// Safe to call repeatedly (on appear and foreground); cheap and offline.
    func refresh() async {
        guard isHealthAvailable else { summary = .unavailable; return }

        var metrics: [MeasuredMetric] = []
        let now = Date()

        for kind in HealthMetricKind.allCases {
            if let value = await currentValue(for: kind), value > 0 {
                metrics.append(MeasuredMetric(kind: kind, value: value, asOf: now))
            }
        }

        summary = HealthSummary(
            metrics: metrics,
            asOf: metrics.isEmpty ? nil : now,
            authorized: hasRequestedAuthorization,
            available: true
        )

        await refreshBaselines()
    }

    /// The single "where am I now" reading for a metric.
    private func currentValue(for kind: HealthMetricKind) async -> Double? {
        switch kind {
        case .sleepHours:    return await lastNightSleepHours()
        case .mindfulMinutes:return await todayMindfulMinutes()
        default:
            guard let id = Self.quantityMap[kind] else { return nil }
            if isCumulative(kind) {
                return await todaySum(id, unit: unit(for: kind))
            } else {
                let raw = await mostRecentValue(id, unit: unit(for: kind))
                // Oxygen saturation is stored as a fraction (1.0 == 100%).
                if kind == .oxygenSaturation, let raw { return raw * 100 }
                return raw
            }
        }
    }

    // MARK: - Baselines (trailing averages for anomaly detection)

    private func refreshBaselines() async {
        var result: [HealthMetricKind: Double] = [:]
        // Cumulative daily metrics: average of daily totals.
        for kind in [HealthMetricKind.steps, .activeEnergy, .exerciseMinutes] {
            if let id = Self.quantityMap[kind],
               let avg = await averageDailyTotal(id, unit: unit(for: kind), days: 14) {
                result[kind] = avg
            }
        }
        // Discrete daily metrics: average of daily averages.
        for kind in [HealthMetricKind.restingHeartRate, .heartRateVariability] {
            if let id = Self.quantityMap[kind],
               let avg = await averageDailyAverage(id, unit: unit(for: kind), days: 14) {
                result[kind] = avg
            }
        }
        // Sleep: average nightly hours.
        if let sleep = await averageNightlySleepHours(days: 14) {
            result[.sleepHours] = sleep
        }
        baselines = result
    }

    // MARK: - Quantity helpers

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let start = calendar.startOfDay(for: Date())
        return await sum(id, unit: unit, from: start, to: Date())
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        )
        let anchor = calendar.startOfDay(for: from)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var total = 0.0
        var found = false
        collection.enumerateStatistics(from: from, to: to) { stats, _ in
            if let q = stats.sumQuantity() {
                total += q.doubleValue(for: unit)
                found = true
            }
        }
        return found ? total : nil
    }

    private func mostRecentValue(_ id: HKQuantityTypeIdentifier, unit: HKUnit, withinDays days: Int = 7) async -> Double? {
        let start = calendar.date(byAdding: .day, value: -days, to: Date())
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }

    private func averageDailyTotal(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: anchor) else { return nil }
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: start, end: anchor, options: [])
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var values: [Double] = []
        collection.enumerateStatistics(from: start, to: anchor) { stats, _ in
            if let q = stats.sumQuantity() { values.append(q.doubleValue(for: unit)) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func averageDailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: anchor) else { return nil }
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: start, end: anchor, options: [])
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: .discreteAverage,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var values: [Double] = []
        collection.enumerateStatistics(from: start, to: anchor) { stats, _ in
            if let q = stats.averageQuantity() { values.append(q.doubleValue(for: unit)) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Sleep (category samples)

    /// Total asleep hours for the most recent night.
    private func lastNightSleepHours() async -> Double? {
        let now = Date()
        // Window from ~2pm yesterday so a single night is captured regardless of
        // the current hour.
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
              let windowStart = calendar.date(byAdding: .hour, value: 14, to: yesterdayStart) else { return nil }
        let hours = await asleepHours(from: windowStart, to: now)
        return hours > 0 ? hours : nil
    }

    private func averageNightlySleepHours(days: Int) async -> Double? {
        let now = Date()
        var nightly: [Double] = []
        for offset in 1...days {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)),
                  let windowStart = calendar.date(byAdding: .hour, value: 14, to: dayStart),
                  let windowEnd = calendar.date(byAdding: .hour, value: 38, to: dayStart) else { continue }
            let hours = await asleepHours(from: windowStart, to: windowEnd)
            if hours > 0 { nightly.append(hours) }
        }
        guard !nightly.isEmpty else { return nil }
        return nightly.reduce(0, +) / Double(nightly.count)
    }

    private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    private func asleepHours(from: Date, to: Date) async -> Double {
        let predicate = HKSamplePredicate.categorySample(
            type: sleepType,
            predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return 0 }
        // Coalesce overlapping intervals before summing. Sleep samples routinely
        // overlap (a coarse "asleep" block plus a staged Core/Deep/REM breakdown of
        // the same minutes, or two sources covering one night), so a naive sum
        // double-counts. We union the intervals and sum the merged spans, so the
        // measured hours stay trustworthy (they feed a displayed number and the
        // anomaly baseline).
        let intervals = samples
            .filter { Self.asleepValues.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        var seconds = 0.0
        var curStart: Date?
        var curEnd: Date?
        for iv in intervals {
            if let cs = curStart, let ce = curEnd {
                if iv.start <= ce {
                    curEnd = max(ce, iv.end)              // overlap: extend
                } else {
                    seconds += ce.timeIntervalSince(cs)   // gap: close the run
                    curStart = iv.start
                    curEnd = iv.end
                }
            } else {
                curStart = iv.start
                curEnd = iv.end
            }
        }
        if let cs = curStart, let ce = curEnd { seconds += ce.timeIntervalSince(cs) }
        return seconds / 3600.0
    }

    // MARK: - Mindful (category samples)

    private func todayMindfulMinutes() async -> Double? {
        let start = calendar.startOfDay(for: Date())
        let predicate = HKSamplePredicate.categorySample(
            type: mindfulType,
            predicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        let seconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let minutes = seconds / 60.0
        return minutes > 0 ? minutes : nil
    }
}
