//
//  DailySnapshot.swift
//  LYFESTYL
//
//  One calendar day of wellness, assembled from every connected source. This is the
//  row the correlation and baseline analysis runs over: sleep, heart-rate variability,
//  resting heart rate, movement, body composition, plus the Garmin-only readiness
//  metrics when a direct Garmin sync is available.
//
//  Every field is optional and stays optional. A day with no watch on the wrist has
//  no resting heart rate, and that is recorded as nothing rather than as a zero. The
//  analysis layer treats nil as "unmeasured" and excludes it, so a gap never drags a
//  baseline down or invents a trend.
//

import SwiftUI

// MARK: - The metric vocabulary

/// Every daily wellness metric the app understands, with its display treatment and
/// the direction that counts as an improvement. Having one enum means new metrics
/// appear in the UI, the baselines and the correlation search without touching
/// three different files.
nonisolated enum WellnessMetric: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    // Sleep
    case sleepDuration
    case sleepEfficiency
    case deepSleepShare
    case remSleepShare
    case bedtimeConsistency

    // Cardiovascular and autonomic
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case walkingHeartRate
    case heartRateRecovery

    // Movement
    case steps
    case activeEnergy
    case exerciseMinutes
    case standHours
    case flightsClimbed
    case timeInDaylight

    // Fitness and composition
    case vo2Max
    case bodyMass
    case bodyFat
    case leanBodyMass

    // Mind
    case mindfulMinutes

    // Garmin-only, present only from imported Garmin data
    case bodyBattery
    case stressLevel
    case trainingReadiness
    /// Garmin's overnight HRV, measured as RMSSD. Deliberately a SEPARATE metric from
    /// `heartRateVariability` (Apple's SDNN): the two quantify different properties of the
    /// beat-to-beat interval series and there is no valid conversion between them, so they
    /// are never averaged together or compared against one another's baseline.
    case hrvRmssd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleepDuration:       "Sleep"
        case .sleepEfficiency:     "Sleep Efficiency"
        case .deepSleepShare:      "Deep Sleep"
        case .remSleepShare:       "REM Sleep"
        case .bedtimeConsistency:  "Bedtime"
        case .restingHeartRate:    "Resting HR"
        case .heartRateVariability:"HRV"
        case .respiratoryRate:     "Respiratory Rate"
        case .oxygenSaturation:    "Blood Oxygen"
        case .wristTemperature:    "Wrist Temp"
        case .walkingHeartRate:    "Walking HR"
        case .heartRateRecovery:   "HR Recovery"
        case .steps:               "Steps"
        case .activeEnergy:        "Active Energy"
        case .exerciseMinutes:     "Exercise"
        case .standHours:          "Stand Hours"
        case .flightsClimbed:      "Flights"
        case .timeInDaylight:      "Daylight"
        case .vo2Max:              "VO2 Max"
        case .bodyMass:            "Weight"
        case .bodyFat:             "Body Fat"
        case .leanBodyMass:        "Lean Mass"
        case .mindfulMinutes:      "Mindful"
        case .bodyBattery:         "Body Battery"
        case .stressLevel:         "Stress"
        case .trainingReadiness:   "Training Readiness"
        case .hrvRmssd:            "HRV (RMSSD)"
        }
    }

    var unit: String {
        switch self {
        case .sleepDuration:       "h"
        case .sleepEfficiency, .deepSleepShare, .remSleepShare, .oxygenSaturation, .bodyFat: "%"
        case .bedtimeConsistency:  "h"
        case .restingHeartRate, .walkingHeartRate: "bpm"
        case .heartRateVariability, .hrvRmssd: "ms"
        case .respiratoryRate:     "br/min"
        case .wristTemperature:    "C"
        case .heartRateRecovery:   "bpm"
        case .steps:               "steps"
        case .activeEnergy:        "kcal"
        case .exerciseMinutes, .timeInDaylight, .mindfulMinutes: "min"
        case .standHours:          "h"
        case .flightsClimbed:      "flights"
        case .vo2Max:              "mL/kg/min"
        case .bodyMass, .leanBodyMass: "kg"
        case .bodyBattery, .trainingReadiness, .stressLevel: ""
        }
    }

    var symbolName: String {
        switch self {
        case .sleepDuration, .sleepEfficiency: "bed.double.fill"
        case .deepSleepShare:      "moon.zzz.fill"
        case .remSleepShare:       "eye.fill"
        case .bedtimeConsistency:  "clock.fill"
        case .restingHeartRate:    "heart.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .respiratoryRate:     "lungs.fill"
        case .oxygenSaturation:    "drop.degreesign.fill"
        case .wristTemperature:    "thermometer.medium"
        case .walkingHeartRate:    "figure.walk.motion"
        case .heartRateRecovery:   "arrow.down.heart.fill"
        case .steps:               "shoeprints.fill"
        case .activeEnergy:        "flame.fill"
        case .exerciseMinutes:     "figure.run"
        case .standHours:          "figure.stand"
        case .flightsClimbed:      "figure.stairs"
        case .timeInDaylight:      "sun.max.fill"
        case .vo2Max:              "lungs.fill"
        case .bodyMass:            "scalemass.fill"
        case .bodyFat:             "percent"
        case .leanBodyMass:        "figure.arms.open"
        case .mindfulMinutes:      "brain.head.profile"
        case .bodyBattery:         "battery.100percent.bolt"
        case .stressLevel:         "bolt.heart.fill"
        case .trainingReadiness:   "gauge.with.dots.needle.67percent"
        case .hrvRmssd:            "waveform.path.ecg.rectangle"
        }
    }

    /// Which life category this metric informs, so it can sit beside the journal.
    var category: InsightCategory {
        switch self {
        case .sleepDuration, .sleepEfficiency, .deepSleepShare, .remSleepShare, .bedtimeConsistency:
            .sleep
        case .steps, .activeEnergy, .exerciseMinutes, .standHours, .flightsClimbed, .vo2Max:
            .activity
        case .mindfulMinutes, .stressLevel:
            .mind
        default:
            .health
        }
    }

    var accent: Color { category.accent }

    /// Which direction is generally favourable. Used to phrase a change neutrally
    /// ("higher than usual") while still letting the UI colour a meaningful move.
    /// `.neutral` means there is no better direction and we must not imply one.
    enum Direction: String, Codable, Sendable { case higherIsBetter, lowerIsBetter, neutral }

    var direction: Direction {
        switch self {
        case .sleepDuration, .sleepEfficiency, .deepSleepShare, .remSleepShare,
             .heartRateVariability, .hrvRmssd, .heartRateRecovery, .steps, .activeEnergy,
             .exerciseMinutes, .standHours, .flightsClimbed, .timeInDaylight,
             .vo2Max, .leanBodyMass, .mindfulMinutes, .bodyBattery, .trainingReadiness:
            .higherIsBetter
        case .restingHeartRate, .respiratoryRate, .walkingHeartRate, .stressLevel:
            .lowerIsBetter
        // Body weight, body fat, blood oxygen, wrist temperature and bedtime have no
        // universally better direction for an individual, so we never grade them.
        case .bodyMass, .bodyFat, .oxygenSaturation, .wristTemperature, .bedtimeConsistency:
            .neutral
        }
    }

    var fractionDigits: Int {
        switch self {
        case .sleepDuration, .heartRateVariability, .hrvRmssd, .respiratoryRate, .vo2Max,
             .bodyMass, .leanBodyMass, .bodyFat, .standHours:
            1
        case .wristTemperature, .bedtimeConsistency:
            2
        default:
            0
        }
    }

    /// Whether this metric is only available through a direct Garmin connection
    /// (Garmin does not mirror these into Apple Health).
    var isGarminExclusive: Bool {
        switch self {
        case .bodyBattery, .stressLevel, .trainingReadiness, .hrvRmssd: true
        default: false
        }
    }

    /// Read this metric off a snapshot.
    func value(from snapshot: DailySnapshot) -> Double? {
        switch self {
        case .sleepDuration:       snapshot.sleep.map { $0.asleepSeconds / 3600 }
        case .sleepEfficiency:     snapshot.sleep?.efficiency.map { $0 * 100 }
        case .deepSleepShare:      snapshot.sleep?.stageFraction(.deep).map { $0 * 100 }
        case .remSleepShare:       snapshot.sleep?.stageFraction(.rem).map { $0 * 100 }
        case .bedtimeConsistency:  snapshot.sleep?.bedtimeHour()
        case .restingHeartRate:    snapshot.restingHeartRate
        case .heartRateVariability:snapshot.heartRateVariabilityMs
        case .respiratoryRate:     snapshot.respiratoryRate
        case .oxygenSaturation:    snapshot.oxygenSaturationPercent
        case .wristTemperature:    snapshot.wristTemperatureDeltaC
        case .walkingHeartRate:    snapshot.walkingHeartRateAverage
        case .heartRateRecovery:   snapshot.heartRateRecoveryOneMinute
        case .steps:               snapshot.steps
        case .activeEnergy:        snapshot.activeEnergyKcal
        case .exerciseMinutes:     snapshot.exerciseMinutes
        case .standHours:          snapshot.standHours
        case .flightsClimbed:      snapshot.flightsClimbed
        case .timeInDaylight:      snapshot.timeInDaylightMinutes
        case .vo2Max:              snapshot.vo2Max
        case .bodyMass:            snapshot.bodyMassKg
        case .bodyFat:             snapshot.bodyFatPercent
        case .leanBodyMass:        snapshot.leanBodyMassKg
        case .mindfulMinutes:      snapshot.mindfulMinutes
        case .bodyBattery:         snapshot.bodyBattery
        case .stressLevel:         snapshot.stressAverage
        case .trainingReadiness:   snapshot.trainingReadiness
        case .hrvRmssd:            snapshot.garminHrvRmssdMs
        }
    }

    /// Format a value with the right precision. Weight metrics respect the user's
    /// unit preference, everything else has one natural unit.
    func format(_ value: Double, includeUnit: Bool = false, weightUnit: WeightUnit = .kg) -> String {
        switch self {
        case .bodyMass, .leanBodyMass:
            return Formatting.weight(kilograms: value, unit: weightUnit, includeUnit: includeUnit)
        case .bedtimeConsistency:
            // Render the continuous hour scale back as a clock time.
            let wrapped = value < 0 ? value + 24 : value
            let h = Int(wrapped)
            let m = Int(((wrapped - Double(h)) * 60).rounded())
            let normalizedHour = m == 60 ? (h + 1) % 24 : h
            let normalizedMinute = m == 60 ? 0 : m
            return String(format: "%d:%02d", normalizedHour, normalizedMinute)
        case .steps, .activeEnergy, .flightsClimbed:
            let number = Formatting.count(value)
            return includeUnit ? "\(number) \(unit)" : number
        default:
            let number = value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
            return includeUnit ? "\(number) \(unit)" : number
        }
    }

    /// Display unit, respecting the weight preference.
    func displayUnit(weightUnit: WeightUnit) -> String {
        switch self {
        case .bodyMass, .leanBodyMass: weightUnit.rawValue
        default: unit
        }
    }
}

// MARK: - The snapshot

/// One day of wellness. Values are canonical: hours for sleep, milliseconds for
/// HRV, beats per minute, kilocalories, kilograms, minutes, degrees Celsius.
nonisolated struct DailySnapshot: Identifiable, Hashable, Codable, Sendable {

    /// Start of the calendar day this describes.
    var date: Date

    var sleep: SleepNight?

    // Cardiovascular and autonomic
    var restingHeartRate: Double?
    /// Heart-rate variability as SDNN in milliseconds, which is what Apple Health
    /// stores. Note SDNN is not RMSSD: the two are related but not interchangeable,
    /// so the analysis compares SDNN only against the user's own SDNN history.
    var heartRateVariabilityMs: Double?
    var respiratoryRate: Double?
    var oxygenSaturationPercent: Double?
    /// Deviation from the wearer's own sleeping wrist-temperature baseline, in
    /// degrees Celsius. Apple stores this as a delta, not an absolute temperature.
    var wristTemperatureDeltaC: Double?
    var walkingHeartRateAverage: Double?
    var heartRateRecoveryOneMinute: Double?
    /// Sleeping breathing disturbances, as a fraction of the night.
    var breathingDisturbances: Double?

    // Movement
    var steps: Double?
    var activeEnergyKcal: Double?
    var basalEnergyKcal: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var flightsClimbed: Double?
    var distanceWalkingRunningMeters: Double?
    var timeInDaylightMinutes: Double?

    // Fitness and composition
    var vo2Max: Double?
    var bodyMassKg: Double?
    var bodyFatPercent: Double?
    var leanBodyMassKg: Double?

    // Mind
    var mindfulMinutes: Double?

    // Garmin-exclusive readiness metrics, present only with a direct Garmin sync.
    var bodyBattery: Double?
    var stressAverage: Double?
    var trainingReadiness: Double?
    /// Garmin's overnight HRV as RMSSD in milliseconds. Kept apart from
    /// `heartRateVariabilityMs` (Apple's SDNN) on purpose: RMSSD and SDNN are different
    /// measures and mixing them would silently corrupt both baselines.
    var garminHrvRmssdMs: Double?

    /// Which sources contributed anything to this day.
    var contributingSources: [DataSource]

    init(
        date: Date,
        sleep: SleepNight? = nil,
        restingHeartRate: Double? = nil,
        heartRateVariabilityMs: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturationPercent: Double? = nil,
        wristTemperatureDeltaC: Double? = nil,
        walkingHeartRateAverage: Double? = nil,
        heartRateRecoveryOneMinute: Double? = nil,
        breathingDisturbances: Double? = nil,
        steps: Double? = nil,
        activeEnergyKcal: Double? = nil,
        basalEnergyKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        standHours: Double? = nil,
        flightsClimbed: Double? = nil,
        distanceWalkingRunningMeters: Double? = nil,
        timeInDaylightMinutes: Double? = nil,
        vo2Max: Double? = nil,
        bodyMassKg: Double? = nil,
        bodyFatPercent: Double? = nil,
        leanBodyMassKg: Double? = nil,
        mindfulMinutes: Double? = nil,
        bodyBattery: Double? = nil,
        stressAverage: Double? = nil,
        trainingReadiness: Double? = nil,
        garminHrvRmssdMs: Double? = nil,
        contributingSources: [DataSource] = []
    ) {
        self.date = date
        self.sleep = sleep
        self.restingHeartRate = restingHeartRate
        self.heartRateVariabilityMs = heartRateVariabilityMs
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturationPercent = oxygenSaturationPercent
        self.wristTemperatureDeltaC = wristTemperatureDeltaC
        self.walkingHeartRateAverage = walkingHeartRateAverage
        self.heartRateRecoveryOneMinute = heartRateRecoveryOneMinute
        self.breathingDisturbances = breathingDisturbances
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.basalEnergyKcal = basalEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.flightsClimbed = flightsClimbed
        self.distanceWalkingRunningMeters = distanceWalkingRunningMeters
        self.timeInDaylightMinutes = timeInDaylightMinutes
        self.vo2Max = vo2Max
        self.bodyMassKg = bodyMassKg
        self.bodyFatPercent = bodyFatPercent
        self.leanBodyMassKg = leanBodyMassKg
        self.mindfulMinutes = mindfulMinutes
        self.bodyBattery = bodyBattery
        self.stressAverage = stressAverage
        self.trainingReadiness = trainingReadiness
        self.garminHrvRmssdMs = garminHrvRmssdMs
        self.contributingSources = contributingSources
    }

    var id: Date { date }

    /// Metrics that actually carry a value on this day, in display order.
    var presentMetrics: [WellnessMetric] {
        WellnessMetric.allCases.filter { $0.value(from: self) != nil }
    }

    var isEmpty: Bool {
        presentMetrics.isEmpty
    }

    /// Total energy where both parts are known.
    var totalEnergyKcal: Double? {
        switch (activeEnergyKcal, basalEnergyKcal) {
        case (let a?, let b?): a + b
        case (let a?, nil):    a
        case (nil, let b?):    b
        default:               nil
        }
    }
}
