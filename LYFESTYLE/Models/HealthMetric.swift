//
//  HealthMetric.swift
//  LYFESTYL
//
//  The MEASURED side of STYL. Everything here comes from Apple HealthKit, so it
//  is real, measured data, never a model guess. These are the ONLY values the app
//  ever renders as actual numbers (the "is every number traceable to measured
//  data?" rule). The journal carries only the user's own organized notes; precise
//  figures must originate here.
//
//  `HealthKitService` fills a `HealthSummary`, which STYL shows in its measured
//  lane. An empty summary (no watch, no data, or not authorized) is a normal state
//  the UI handles by simply omitting the measured lane.
//

import SwiftUI

/// A measured health metric we read from HealthKit. Each maps to one life
/// category so it can sit beside that category's qualitative standing.
enum HealthMetricKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case steps
    case activeEnergy           // kcal, measured (distinct from inferred food calories)
    case exerciseMinutes
    case walkingRunningDistance
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case sleepHours             // measured asleep duration (not the inferred SLEEP rank)
    case mindfulMinutes

    var id: String { rawValue }

    /// Which life category this measured metric informs.
    var category: InsightCategory {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .walkingRunningDistance:
            .activity
        case .restingHeartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation:
            .health
        case .sleepHours:
            .sleep
        case .mindfulMinutes:
            .mind
        }
    }

    var label: String {
        switch self {
        case .steps:                 "Steps"
        case .activeEnergy:          "Active Energy"
        case .exerciseMinutes:       "Exercise"
        case .walkingRunningDistance:"Distance"
        case .restingHeartRate:      "Resting HR"
        case .heartRateVariability:  "HRV"
        case .respiratoryRate:       "Respiratory"
        case .oxygenSaturation:      "Blood Oxygen"
        case .sleepHours:            "Sleep"
        case .mindfulMinutes:        "Mindful"
        }
    }

    var unit: String {
        switch self {
        case .steps:                 "steps"
        case .activeEnergy:          "kcal"
        case .exerciseMinutes:       "min"
        case .walkingRunningDistance:"mi"
        case .restingHeartRate:      "bpm"
        case .heartRateVariability:  "ms"
        case .respiratoryRate:       "br/min"
        case .oxygenSaturation:      "%"
        case .sleepHours:            "h"
        case .mindfulMinutes:        "min"
        }
    }

    var symbolName: String {
        switch self {
        case .steps:                 "shoeprints.fill"
        case .activeEnergy:          "flame.fill"
        case .exerciseMinutes:       "figure.run"
        case .walkingRunningDistance:"point.topleft.down.to.point.bottomright.curvepath.fill"
        case .restingHeartRate:      "heart.fill"
        case .heartRateVariability:  "waveform.path.ecg"
        case .respiratoryRate:       "lungs.fill"
        case .oxygenSaturation:      "drop.degreesign.fill"
        case .sleepHours:            "bed.double.fill"
        case .mindfulMinutes:        "brain.head.profile"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .walkingRunningDistance, .heartRateVariability: 1
        case .sleepHours: 1
        default: 0
        }
    }

    /// Format a measured value with the right precision (unit shown separately so
    /// the card can lay value and unit out with distinct type weights).
    func format(_ value: Double, includeUnit: Bool = false) -> String {
        let digits = (self == .heartRateVariability) ? 0 : fractionDigits
        let number = value.formatted(.number.precision(.fractionLength(0...digits)))
        return includeUnit ? "\(number) \(unit)" : number
    }
}

/// A single measured datapoint. `value` is always sourced from HealthKit.
struct MeasuredMetric: Identifiable, Hashable, Codable {
    let kind: HealthMetricKind
    let value: Double
    /// When the measurement applies (today's tally, or the most recent reading).
    let asOf: Date

    var id: HealthMetricKind { kind }
    var display: String { kind.format(value) }
    var displayWithUnit: String { kind.format(value, includeUnit: true) }
}

/// A bundle of today's / most-recent measured values. Empty is a fully supported,
/// normal state (no Apple Watch, no data, or read access not granted).
struct HealthSummary: Codable, Hashable {
    var metrics: [MeasuredMetric]
    var asOf: Date?
    /// User granted read access to at least some types.
    var authorized: Bool
    /// HKHealthStore.isHealthDataAvailable on this device.
    var available: Bool

    static let unavailable = HealthSummary(metrics: [], asOf: nil, authorized: false, available: false)
    static let empty = HealthSummary(metrics: [], asOf: nil, authorized: false, available: true)

    var isEmpty: Bool { metrics.isEmpty }

    func metric(_ kind: HealthMetricKind) -> MeasuredMetric? {
        metrics.first { $0.kind == kind }
    }

    func metrics(for category: InsightCategory) -> [MeasuredMetric] {
        metrics.filter { $0.kind.category == category }
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}
