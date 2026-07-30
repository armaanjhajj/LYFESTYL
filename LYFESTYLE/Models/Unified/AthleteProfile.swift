//
//  AthleteProfile.swift
//  LYFESTYL
//
//  The handful of personal anchors that every training-load calculation needs:
//  maximum and resting heart rate, functional threshold power, threshold running
//  pace, body mass, age and sex.
//
//  These are the difference between a real analysis and a plausible-looking one. A
//  TRIMP computed against a guessed max heart rate is a guess, and this type is
//  built so the app always knows WHICH it has. Every anchor exposes both a value and
//  a `Provenance`, so the UI can say "using your measured max of 191" or "estimated
//  from your age, set your real one for sharper numbers" instead of quietly
//  presenting an estimate as fact.
//
//  Resolution order for each anchor, best first:
//    1. the user's own explicit entry
//    2. observed from their actual data (highest heart rate ever recorded in a
//       session, resting heart rate from Apple Health, FTP written by a bike computer)
//    3. a published population formula, clearly labelled as an estimate
//

import Foundation
import Observation

// MARK: - Provenance

/// Where an anchor value came from. Drives honest labelling everywhere it is used.
nonisolated enum AnchorProvenance: String, Codable, Hashable, Sendable {
    /// The user entered it.
    case userEntered
    /// Measured from the user's own recorded data.
    case observed
    /// A published population estimate, not this person's measurement.
    case estimated

    var label: String {
        switch self {
        case .userEntered: "you set this"
        case .observed:    "from your data"
        case .estimated:   "estimated"
        }
    }

    /// Whether numbers derived from this anchor should be presented with a caveat.
    var isEstimate: Bool { self == .estimated }
}

/// A resolved anchor: the number plus how confident we are in where it came from.
nonisolated struct Anchor: Hashable, Sendable {
    var value: Double
    var provenance: AnchorProvenance

    var isEstimate: Bool { provenance.isEstimate }
}

// MARK: - Biological sex (only where a formula genuinely requires it)

/// Used only by formulas that are published with sex-specific coefficients, notably
/// the exponential TRIMP weighting. Defaults to `unspecified`, in which case the
/// analysis falls back to a sex-neutral method rather than assuming.
nonisolated enum AthleteSex: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case male, female, unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male:        "Male"
        case .female:      "Female"
        case .unspecified: "Prefer not to say"
        }
    }
}

// MARK: - Snapshot

/// An immutable, `Sendable` copy of the resolved anchors.
///
/// The analysis layer takes ONE of these rather than the observable profile object.
/// That keeps every calculation a pure function of plain values, which means the whole
/// analysis can run off the main actor without any isolation gymnastics, and means a
/// computation can never observe the profile changing halfway through.
nonisolated struct ProfileSnapshot: Hashable, Sendable {
    var maxHeartRate: Anchor?
    var restingHeartRate: Anchor?
    var functionalThresholdPower: Anchor?
    var thresholdPaceSecPerKm: Anchor?
    var bodyMassKg: Anchor?
    var age: Int?
    var sex: AthleteSex

    init(
        maxHeartRate: Anchor? = nil,
        restingHeartRate: Anchor? = nil,
        functionalThresholdPower: Anchor? = nil,
        thresholdPaceSecPerKm: Anchor? = nil,
        bodyMassKg: Anchor? = nil,
        age: Int? = nil,
        sex: AthleteSex = .unspecified
    ) {
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.functionalThresholdPower = functionalThresholdPower
        self.thresholdPaceSecPerKm = thresholdPaceSecPerKm
        self.bodyMassKg = bodyMassKg
        self.age = age
        self.sex = sex
    }

    /// An empty snapshot, for previews and for the state before anything is known.
    static let unknown = ProfileSnapshot()

    /// The five heart-rate zone boundaries as fractions of heart-rate RESERVE (the
    /// Karvonen method), which is more robust across individuals than percent-of-max
    /// because it accounts for resting heart rate.
    ///
    /// Zone 1 below 60 percent, Zone 2 60 to 70, Zone 3 70 to 80, Zone 4 80 to 90,
    /// Zone 5 above 90: the conventional five-zone reserve boundaries.
    static let zoneReserveBounds: [Double] = [0.60, 0.70, 0.80, 0.90]

    /// Sanity windows. Values outside these are rejected as sensor noise rather than
    /// quietly corrupting every load number that follows. They live here, on the
    /// `Sendable` snapshot, so the off-main import path can reach them.
    static let plausibleMaxHeartRate: ClosedRange<Double> = 120...230
    static let plausibleRestingHeartRate: ClosedRange<Double> = 30...110

    var heartRateReserve: Double? {
        guard let maxHR = maxHeartRate?.value, let restHR = restingHeartRate?.value,
              maxHR > restHR else { return nil }
        return maxHR - restHR
    }

    /// Absolute zone boundaries in beats per minute, being the upper edge of zones 1
    /// through 4. Nil until both anchors are known.
    var heartRateZoneBounds: [Double]? {
        guard let restHR = restingHeartRate?.value, let reserve = heartRateReserve, reserve > 20 else {
            return nil
        }
        return Self.zoneReserveBounds.map { restHR + $0 * reserve }
    }

    func zone(forHeartRate bpm: Double) -> Int? {
        guard let bounds = heartRateZoneBounds else { return nil }
        for (index, bound) in bounds.enumerated() where bpm < bound { return index }
        return bounds.count
    }

    func heartRateReserveFraction(_ bpm: Double) -> Double? {
        guard let restHR = restingHeartRate?.value, let reserve = heartRateReserve, reserve > 0 else {
            return nil
        }
        return ((bpm - restHR) / reserve).clamped(to: 0...1)
    }

    var canScoreHeartRateLoad: Bool { heartRateReserve != nil }

    /// Whether any anchor in use is a population estimate rather than this person's
    /// own measurement, so the UI can offer to sharpen it.
    var reliesOnEstimates: Bool {
        [maxHeartRate?.provenance, restingHeartRate?.provenance]
            .compactMap { $0 }
            .contains { $0.isEstimate }
    }
}

// MARK: - Profile

@MainActor
@Observable
final class AthleteProfile {

    // User-entered overrides. Nil means "not set, fall back".
    var maxHeartRateOverride: Double? { didSet { save() } }
    var restingHeartRateOverride: Double? { didSet { save() } }
    var functionalThresholdPowerOverride: Double? { didSet { save() } }
    /// Threshold running pace in seconds per kilometer, the pace sustainable for
    /// roughly an hour. Anchors running training-load scoring.
    var thresholdPaceSecPerKmOverride: Double? { didSet { save() } }
    var bodyMassKgOverride: Double? { didSet { save() } }
    var birthDate: Date? { didSet { save() } }
    var sex: AthleteSex { didSet { save() } }

    // Values observed from the user's real data, refreshed by the sync layer.
    private(set) var observedMaxHeartRate: Double?
    private(set) var observedRestingHeartRate: Double?
    private(set) var observedFunctionalThresholdPower: Double?
    private(set) var observedThresholdPaceSecPerKm: Double?
    private(set) var observedBodyMassKg: Double?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let maxHR = "athlete_max_hr"
        static let restHR = "athlete_rest_hr"
        static let ftp = "athlete_ftp"
        static let thresholdPace = "athlete_threshold_pace"
        static let bodyMass = "athlete_body_mass"
        static let birthDate = "athlete_birth_date"
        static let sex = "athlete_sex"
    }

    init() {
        maxHeartRateOverride = defaults.optionalDouble(Key.maxHR)
        restingHeartRateOverride = defaults.optionalDouble(Key.restHR)
        functionalThresholdPowerOverride = defaults.optionalDouble(Key.ftp)
        thresholdPaceSecPerKmOverride = defaults.optionalDouble(Key.thresholdPace)
        bodyMassKgOverride = defaults.optionalDouble(Key.bodyMass)
        birthDate = defaults.object(forKey: Key.birthDate) as? Date
        sex = defaults.string(forKey: Key.sex).flatMap(AthleteSex.init(rawValue:)) ?? .unspecified
    }

    private func save() {
        defaults.setOptionalDouble(maxHeartRateOverride, Key.maxHR)
        defaults.setOptionalDouble(restingHeartRateOverride, Key.restHR)
        defaults.setOptionalDouble(functionalThresholdPowerOverride, Key.ftp)
        defaults.setOptionalDouble(thresholdPaceSecPerKmOverride, Key.thresholdPace)
        defaults.setOptionalDouble(bodyMassKgOverride, Key.bodyMass)
        if let birthDate { defaults.set(birthDate, forKey: Key.birthDate) }
        else { defaults.removeObject(forKey: Key.birthDate) }
        defaults.set(sex.rawValue, forKey: Key.sex)
    }

    // MARK: - Learning from the user's own data

    /// Fold in what the data actually shows. Called by the sync layer after a
    /// refresh. Deliberately does NOT overwrite user overrides.
    func learn(
        observedMaxHeartRate: Double? = nil,
        observedRestingHeartRate: Double? = nil,
        observedFTP: Double? = nil,
        observedThresholdPaceSecPerKm: Double? = nil,
        observedBodyMassKg: Double? = nil
    ) {
        // Max heart rate only ever ratchets upward from observation: a session where
        // the strap dropped out does not lower a true maximum.
        if let value = observedMaxHeartRate, ProfileSnapshot.plausibleMaxHeartRate.contains(value) {
            self.observedMaxHeartRate = max(self.observedMaxHeartRate ?? 0, value)
        }
        if let value = observedRestingHeartRate, ProfileSnapshot.plausibleRestingHeartRate.contains(value) {
            self.observedRestingHeartRate = value
        }
        if let value = observedFTP, value > 40, value < 600 {
            self.observedFunctionalThresholdPower = value
        }
        if let value = observedThresholdPaceSecPerKm, value > 120, value < 900 {
            self.observedThresholdPaceSecPerKm = value
        }
        if let value = observedBodyMassKg, value > 25, value < 350 {
            self.observedBodyMassKg = value
        }
    }


    // MARK: - Resolved anchors

    var age: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Maximum heart rate. Prefers what the user set, then the highest value ever
    /// actually recorded, then the Tanaka age formula.
    ///
    /// Tanaka, Monahan and Seals (2001), J Am Coll Cardiol 37:153-156:
    ///     HRmax = 208 - 0.7 x age
    /// It is better supported across ages than the folk "220 minus age", which
    /// systematically overestimates in the young and underestimates in the old.
    var maxHeartRate: Anchor? {
        if let value = maxHeartRateOverride { return Anchor(value: value, provenance: .userEntered) }
        if let value = observedMaxHeartRate { return Anchor(value: value, provenance: .observed) }
        if let age { return Anchor(value: 208 - 0.7 * Double(age), provenance: .estimated) }
        return nil
    }

    /// Resting heart rate. Apple Health computes this daily, so the observed value
    /// is usually real. Falls back to a population figure only as a last resort.
    var restingHeartRate: Anchor? {
        if let value = restingHeartRateOverride { return Anchor(value: value, provenance: .userEntered) }
        if let value = observedRestingHeartRate { return Anchor(value: value, provenance: .observed) }
        return nil
    }

    /// Heart-rate reserve, the span the training zones are cut from.
    var heartRateReserve: Double? {
        guard let maxHR = maxHeartRate?.value, let restHR = restingHeartRate?.value,
              maxHR > restHR else { return nil }
        return maxHR - restHR
    }

    /// Functional threshold power in watts. A bike computer can write this into
    /// Apple Health directly, which is the observed case.
    var functionalThresholdPower: Anchor? {
        if let value = functionalThresholdPowerOverride { return Anchor(value: value, provenance: .userEntered) }
        if let value = observedFunctionalThresholdPower { return Anchor(value: value, provenance: .observed) }
        return nil
    }

    /// Threshold running pace, seconds per kilometer.
    var thresholdPaceSecPerKm: Anchor? {
        if let value = thresholdPaceSecPerKmOverride { return Anchor(value: value, provenance: .userEntered) }
        if let value = observedThresholdPaceSecPerKm { return Anchor(value: value, provenance: .observed) }
        return nil
    }

    var bodyMassKg: Anchor? {
        if let value = bodyMassKgOverride { return Anchor(value: value, provenance: .userEntered) }
        if let value = observedBodyMassKg { return Anchor(value: value, provenance: .observed) }
        return nil
    }

    // MARK: - Zones

    /// Absolute heart-rate boundaries between the five zones, in beats per minute.
    /// Four numbers, being the upper edge of zones 1 through 4. Nil until both a max
    /// and a resting heart rate are known, because a zone chart from a guess is
    /// worse than no zone chart.
    var heartRateZoneBounds: [Double]? {
        guard let restHR = restingHeartRate?.value, let reserve = heartRateReserve, reserve > 20 else {
            return nil
        }
        return ProfileSnapshot.zoneReserveBounds.map { restHR + $0 * reserve }
    }

    /// Which zone (0 through 4) a heart rate falls in. Nil when zones are unknown.
    func zone(forHeartRate bpm: Double) -> Int? {
        guard let bounds = heartRateZoneBounds else { return nil }
        for (index, bound) in bounds.enumerated() where bpm < bound { return index }
        return bounds.count   // above the last boundary: zone 5, index 4
    }

    /// Heart rate as a fraction of reserve, the input to the exponential TRIMP.
    func heartRateReserveFraction(_ bpm: Double) -> Double? {
        guard let restHR = restingHeartRate?.value, let reserve = heartRateReserve, reserve > 0 else {
            return nil
        }
        return ((bpm - restHR) / reserve).clamped(to: 0...1)
    }

    /// Whether there is enough profile to score heart-rate based training load.
    var canScoreHeartRateLoad: Bool { heartRateReserve != nil }

    /// Whether any anchor in use is a population estimate rather than this person's
    /// own number, so the UI can offer to sharpen it.
    var reliesOnEstimates: Bool { snapshot.reliesOnEstimates }

    /// The immutable value the analysis layer consumes. Take this once at the start of
    /// a computation so nothing can shift underneath it.
    var snapshot: ProfileSnapshot {
        ProfileSnapshot(
            maxHeartRate: maxHeartRate,
            restingHeartRate: restingHeartRate,
            functionalThresholdPower: functionalThresholdPower,
            thresholdPaceSecPerKm: thresholdPaceSecPerKm,
            bodyMassKg: bodyMassKg,
            age: age,
            sex: sex
        )
    }

    /// The anchors still missing that would most improve the analysis, in priority
    /// order. Drives the "sharpen your numbers" prompt.
    var missingAnchors: [String] {
        var missing: [String] = []
        if maxHeartRate == nil { missing.append("Max heart rate") }
        if restingHeartRate == nil { missing.append("Resting heart rate") }
        if birthDate == nil && maxHeartRateOverride == nil { missing.append("Date of birth") }
        return missing
    }
}

// MARK: - Small helpers

nonisolated extension UserDefaults {
    /// `double(forKey:)` returns 0 for a missing key, which is indistinguishable
    /// from a real zero. These keep "unset" honest.
    func optionalDouble(_ key: String) -> Double? {
        object(forKey: key) as? Double
    }

    func setOptionalDouble(_ value: Double?, _ key: String) {
        if let value { set(value, forKey: key) } else { removeObject(forKey: key) }
    }
}
