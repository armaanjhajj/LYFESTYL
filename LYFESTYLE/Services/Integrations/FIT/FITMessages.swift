//
//  FITMessages.swift
//  LYFESTYL
//
//  Typed views over raw `FITMessage` field numbers. The decoder handles the binary
//  format; this file knows what the numbers MEAN.
//
//  Field numbers, scales, offsets and units below are taken from the FIT Global Profile
//  (version 21.208.0) and are written inline next to each accessor so any value can be
//  checked against the specification without leaving the file.
//
//  Two things this layer is responsible for:
//
//    1. SCALE AND OFFSET. FIT stores integers with a documented divisor, so a raw
//       distance of 360000 with scale 100 is 3600.0 meters, and altitude is
//       `raw / 5 - 500` meters. Getting one of these wrong produces numbers that look
//       plausible and are wrong by a factor of ten, so each is stated explicitly.
//
//    2. PREFERRING THE ENHANCED FIELD. Newer devices write `enhancedSpeed` and
//       `enhancedAltitude` (32-bit, wider range) alongside the legacy 16-bit fields.
//       Where both exist the enhanced one is authoritative, because the legacy field
//       saturates: altitude clips at 6553.5 m and speed at 65.535 m/s.
//
//  Everything converts into the app's canonical units: seconds, meters, meters per
//  second, kilograms, watts, beats per minute, degrees Celsius.
//

import Foundation

// MARK: - Global message numbers

/// The FIT global message numbers this app reads.
nonisolated enum FITMesg {
    static let fileID: UInt16 = 0
    static let userProfile: UInt16 = 3
    static let sport: UInt16 = 12
    static let session: UInt16 = 18
    static let lap: UInt16 = 19
    static let record: UInt16 = 20
    static let event: UInt16 = 21
    static let deviceInfo: UInt16 = 23
    static let weightScale: UInt16 = 30
    static let activity: UInt16 = 34
    static let monitoring: UInt16 = 55
    static let hrv: UInt16 = 78
    static let monitoringInfo: UInt16 = 103
    static let timeInZone: UInt16 = 216
    static let set: UInt16 = 225
    static let stressLevel: UInt16 = 227
    static let maxMetData: UInt16 = 229
    static let spo2Data: UInt16 = 269
    static let sleepLevel: UInt16 = 275
    static let respirationRate: UInt16 = 297
    static let hsaStressData: UInt16 = 306
    static let split: UInt16 = 312
    static let hsaBodyBatteryData: UInt16 = 314
    static let sleepAssessment: UInt16 = 346
    static let hrvStatusSummary: UInt16 = 370
    static let hrvValue: UInt16 = 371
}

// MARK: - Reading helpers

nonisolated extension FITMessage {

    /// Raw numeric value of a field.
    func raw(_ field: UInt8) -> Double? { self[field]?.doubleValue }

    /// Value with the profile's scale and offset applied: `raw / scale - offset`.
    func scaled(_ field: UInt8, scale: Double, offset: Double = 0) -> Double? {
        guard let raw = raw(field), scale != 0 else { return nil }
        return raw / scale - offset
    }

    /// A FIT `dateTime` field, converted from the FIT epoch.
    func date(_ field: UInt8) -> Date? { FITTime.date(from: raw(field)) }

    /// An integer enum value.
    func enumValue(_ field: UInt8) -> Int? { raw(field).map { Int($0) } }

    func string(_ field: UInt8) -> String? { self[field]?.stringValue }

    /// An array field, with the profile scale applied to every element.
    func scaledArray(_ field: UInt8, scale: Double) -> [Double]? {
        guard let values = self[field]?.arrayValue, scale != 0 else { return nil }
        return values.map { $0 / scale }
    }

    /// A latitude or longitude, stored in "semicircles": degrees = semicircles x 180 / 2^31.
    func degrees(_ field: UInt8) -> Double? {
        guard let raw = raw(field) else { return nil }
        let degrees = raw * (180.0 / 2147483648.0)
        // Reject the null island and out-of-range values: a GPS fix at exactly 0,0 is a
        // sensor artifact, not a location anyone trained at.
        guard degrees.isFinite, abs(degrees) > 0.000001, abs(degrees) <= 180 else { return nil }
        return degrees
    }

    /// Prefer an enhanced (32-bit) field over its legacy (16-bit) counterpart, since the
    /// legacy field saturates.
    func preferEnhanced(_ enhanced: UInt8, legacy: UInt8, scale: Double, offset: Double = 0) -> Double? {
        scaled(enhanced, scale: scale, offset: offset) ?? scaled(legacy, scale: scale, offset: offset)
    }
}

// MARK: - file_id (0)

nonisolated struct FITFileID {
    /// `file` enum: 4 = activity, 32 = monitoring_b, 44 = monitoring_daily, 49 = sleep.
    var type: Int?
    var manufacturer: Int?
    var product: Int?
    var serialNumber: Double?
    var timeCreated: Date?

    init(_ m: FITMessage) {
        type = m.enumValue(0)
        manufacturer = m.enumValue(1)
        product = m.enumValue(2)
        serialNumber = m.raw(3)
        timeCreated = m.date(4)
    }

    /// FIT `file` enum values that matter here.
    enum Kind: Int {
        case activity = 4
        case monitoringA = 15
        case monitoringB = 32
        case monitoringDaily = 28
        case sleep = 49
        case weightScale = 9
    }

    var kind: Kind? { type.flatMap(Kind.init(rawValue:)) }

    /// Whether this is a recorded workout as opposed to a wellness or daily file.
    var isActivity: Bool { kind == .activity }
}

// MARK: - session (18)

/// A workout's summary record. This is the single richest message in a Garmin activity
/// file, and it is where Garmin's own computed metrics live: normalized power, training
/// stress score, intensity factor, time in each heart-rate zone, session RMSSD, and the
/// user's own RPE if they rated the session on the watch.
nonisolated struct FITSession {
    var timestamp: Date?
    var startTime: Date?
    /// FIT `sport` enum.
    var sport: Int?
    /// FIT `subSport` enum, which is what distinguishes a trail run from a treadmill run.
    var subSport: Int?

    var totalElapsedSeconds: Double?
    var totalTimerSeconds: Double?
    var totalMovingSeconds: Double?
    var totalDistanceMeters: Double?
    var totalCalories: Double?

    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var minHeartRate: Double?
    var averageSpeedMps: Double?
    var maxSpeedMps: Double?
    var averageCadence: Double?
    var maxCadence: Double?
    var averagePowerWatts: Double?
    var maxPowerWatts: Double?
    var normalizedPowerWatts: Double?
    var thresholdPowerWatts: Double?
    var trainingStressScore: Double?
    var intensityFactor: Double?

    var totalAscentMeters: Double?
    var totalDescentMeters: Double?
    var averageAltitudeMeters: Double?
    var maxAltitudeMeters: Double?
    var minAltitudeMeters: Double?

    var averageTemperatureC: Double?
    var maxTemperatureC: Double?

    // Running dynamics.
    var averageVerticalOscillationMm: Double?
    var averageStanceTimeMs: Double?
    var averageStepLengthMm: Double?
    var averageRespirationRate: Double?

    // Garmin's own physiology outputs.
    var totalTrainingEffect: Double?
    var totalAnaerobicTrainingEffect: Double?
    /// Session RMSSD in milliseconds. Note this is RMSSD, not the SDNN that Apple Health
    /// stores, so the two are never compared directly.
    var rmssdHrvMs: Double?
    var sdrrHrvMs: Double?
    var averageSpo2: Double?
    var averageStress: Double?
    /// Rate of perceived exertion as recorded on the watch, on a 0 to 100 scale.
    var workoutRpe: Double?
    /// How the session felt, 0 to 100.
    var workoutFeel: Double?

    /// Seconds in each heart-rate zone, straight from the device's own zone setup.
    var timeInHeartRateZoneSeconds: [Double]?
    var timeInPowerZoneSeconds: [Double]?

    var startLatitude: Double?
    var startLongitude: Double?
    var numberOfLaps: Double?
    var poolLengthMeters: Double?
    var totalWorkJoules: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        startTime = m.date(2)
        sport = m.enumValue(5)
        subSport = m.enumValue(6)

        // Times are stored in milliseconds (scale 1000).
        totalElapsedSeconds = m.scaled(7, scale: 1000)
        totalTimerSeconds = m.scaled(8, scale: 1000)
        totalMovingSeconds = m.scaled(59, scale: 1000)
        totalDistanceMeters = m.scaled(9, scale: 100)
        totalCalories = m.raw(11)

        averageHeartRate = m.raw(16)
        maxHeartRate = m.raw(17)
        minHeartRate = m.raw(64)
        // enhancedAvgSpeed (124) / enhancedMaxSpeed (125) supersede avgSpeed (14) / maxSpeed (15).
        averageSpeedMps = m.preferEnhanced(124, legacy: 14, scale: 1000)
        maxSpeedMps = m.preferEnhanced(125, legacy: 15, scale: 1000)
        averageCadence = m.raw(18)
        maxCadence = m.raw(19)
        averagePowerWatts = m.raw(20)
        maxPowerWatts = m.raw(21)
        normalizedPowerWatts = m.raw(34)
        thresholdPowerWatts = m.raw(45)
        trainingStressScore = m.scaled(35, scale: 10)
        intensityFactor = m.scaled(36, scale: 1000)

        totalAscentMeters = m.raw(22)
        totalDescentMeters = m.raw(23)
        // Altitude: raw / 5 - 500 meters. enhancedAvgAltitude (126) beats avgAltitude (49).
        averageAltitudeMeters = m.preferEnhanced(126, legacy: 49, scale: 5, offset: 500)
        maxAltitudeMeters = m.preferEnhanced(128, legacy: 50, scale: 5, offset: 500)
        minAltitudeMeters = m.preferEnhanced(127, legacy: 71, scale: 5, offset: 500)

        averageTemperatureC = m.raw(57)
        maxTemperatureC = m.raw(58)

        averageVerticalOscillationMm = m.scaled(89, scale: 10)
        averageStanceTimeMs = m.scaled(91, scale: 10)
        averageStepLengthMm = m.scaled(134, scale: 10)
        // enhancedAvgRespirationRate (169, scale 100) is finer than avgRespirationRate (147).
        averageRespirationRate = m.scaled(169, scale: 100) ?? m.raw(147)

        totalTrainingEffect = m.scaled(24, scale: 10)
        totalAnaerobicTrainingEffect = m.scaled(137, scale: 10)
        rmssdHrvMs = m.raw(198)
        sdrrHrvMs = m.raw(197)
        averageSpo2 = m.raw(194)
        averageStress = m.raw(195)
        workoutRpe = m.raw(193)
        workoutFeel = m.raw(192)

        timeInHeartRateZoneSeconds = m.scaledArray(65, scale: 1000)
        timeInPowerZoneSeconds = m.scaledArray(68, scale: 1000)

        startLatitude = m.degrees(3)
        startLongitude = m.degrees(4)
        numberOfLaps = m.raw(26)
        poolLengthMeters = m.scaled(44, scale: 100)
        totalWorkJoules = m.raw(48)
    }

    /// Garmin records RPE on a 0 to 100 scale; the app's canonical scale is 0 to 10.
    var perceivedEffortOutOfTen: Double? {
        guard let workoutRpe, workoutRpe > 0 else { return nil }
        return (workoutRpe / 10).clamped(to: 0...10)
    }

    /// Moving time, preferring the most specific figure the device recorded.
    var effectiveMovingSeconds: Double? {
        totalMovingSeconds ?? totalTimerSeconds ?? totalElapsedSeconds
    }
}

// MARK: - record (20)

/// One sample along a workout. Thousands of these make up the series that aerobic
/// decoupling, normalized power, grade adjustment and zone occupancy are computed from,
/// none of which is possible from Apple Health for a Garmin session.
nonisolated struct FITRecord {
    var timestamp: Date?
    var latitude: Double?
    var longitude: Double?
    var distanceMeters: Double?
    var speedMps: Double?
    var altitudeMeters: Double?
    var heartRate: Double?
    var cadence: Double?
    var powerWatts: Double?
    var temperatureC: Double?
    var gradePercent: Double?
    var verticalOscillationMm: Double?
    var stanceTimeMs: Double?
    var stepLengthMm: Double?
    var respirationRate: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        latitude = m.degrees(0)
        longitude = m.degrees(1)
        distanceMeters = m.scaled(5, scale: 100)
        // enhancedSpeed (73) supersedes speed (6): the legacy field saturates at 65.535 m/s.
        speedMps = m.preferEnhanced(73, legacy: 6, scale: 1000)
        // enhancedAltitude (78) supersedes altitude (2); both are raw / 5 - 500 meters.
        altitudeMeters = m.preferEnhanced(78, legacy: 2, scale: 5, offset: 500)
        heartRate = m.raw(3)
        // cadence256 (52, scale 256) is finer than cadence (4) where present.
        cadence = m.scaled(52, scale: 256) ?? m.raw(4)
        powerWatts = m.raw(7)
        temperatureC = m.raw(13)
        gradePercent = m.scaled(9, scale: 100)
        verticalOscillationMm = m.scaled(39, scale: 10)
        stanceTimeMs = m.scaled(41, scale: 10)
        stepLengthMm = m.scaled(85, scale: 10)
        respirationRate = m.scaled(108, scale: 100) ?? m.raw(99)
    }

    var hasPosition: Bool { latitude != nil && longitude != nil }
}

// MARK: - lap (19)

nonisolated struct FITLap {
    var timestamp: Date?
    var startTime: Date?
    var totalElapsedSeconds: Double?
    var totalTimerSeconds: Double?
    var totalDistanceMeters: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var averageCadence: Double?
    var averageSpeedMps: Double?
    var maxSpeedMps: Double?
    var averagePowerWatts: Double?
    var totalAscentMeters: Double?
    var totalDescentMeters: Double?
    var messageIndex: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        startTime = m.date(2)
        totalElapsedSeconds = m.scaled(7, scale: 1000)
        totalTimerSeconds = m.scaled(8, scale: 1000)
        totalDistanceMeters = m.scaled(9, scale: 100)
        // Lap numbers its fields DIFFERENTLY from session: here avgHeartRate is 15 and
        // maxHeartRate is 16, where session uses 16 and 17. Reusing session's numbers
        // would silently read max as average and cadence as max.
        averageHeartRate = m.raw(15)
        maxHeartRate = m.raw(16)
        averageCadence = m.raw(17)
        averageSpeedMps = m.preferEnhanced(110, legacy: 13, scale: 1000)
        maxSpeedMps = m.preferEnhanced(111, legacy: 14, scale: 1000)
        averagePowerWatts = m.raw(19)
        totalAscentMeters = m.raw(21)
        totalDescentMeters = m.raw(22)
        messageIndex = m.raw(254)
    }
}

// MARK: - set (225)

/// One set of resistance training, as a Garmin watch records it in a strength activity.
/// Rest periods are recorded as their own set with `setType == 0`.
nonisolated struct FITSet {
    var timestamp: Date?
    var startTime: Date?
    var durationSeconds: Double?
    var repetitions: Int?
    /// Weight in kilograms. Note the unusual scale of 16.
    var weightKg: Double?
    /// 0 = rest, 1 = active.
    var setType: Int?
    /// FIT `exerciseCategory` values, which name the movement family.
    var categories: [Double]?
    var categorySubtypes: [Double]?
    var messageIndex: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(254)
        startTime = m.date(6)
        durationSeconds = m.scaled(0, scale: 1000)
        repetitions = m.raw(3).map { Int($0) }
        // weight is stored with scale 16, so a raw 1320 is 82.5 kg.
        weightKg = m.scaled(4, scale: 16)
        setType = m.enumValue(5)
        categories = m[7]?.arrayValue
        categorySubtypes = m[8]?.arrayValue
        messageIndex = m.raw(10)
    }

    /// Whether this record is a working set rather than a rest interval.
    var isActive: Bool { setType == 1 }
}

// MARK: - Wellness messages

/// A sleep-stage transition. Each message marks the moment a stage BEGAN, so a night is
/// reconstructed by pairing consecutive timestamps.
nonisolated struct FITSleepLevel {
    var timestamp: Date?
    /// 0 unmeasurable, 1 awake, 2 light, 3 deep, 4 rem.
    var level: Int?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        level = m.enumValue(0)
    }

    /// Map onto the app's stage vocabulary. Garmin's "light" is Apple's "core".
    var sleepStage: SleepStage? {
        switch level {
        case 1: .awake
        case 2: .core
        case 3: .deep
        case 4: .rem
        case 0: .unspecified
        default: nil
        }
    }
}

/// Garmin's HRV status summary, recorded overnight. Values are RMSSD in milliseconds.
nonisolated struct FITHRVStatusSummary {
    var timestamp: Date?
    var weeklyAverageMs: Double?
    var lastNightAverageMs: Double?
    var lastNightFiveMinuteHighMs: Double?
    var baselineLowUpperMs: Double?
    var baselineBalancedLowerMs: Double?
    var baselineBalancedUpperMs: Double?
    /// 0 none, 1 poor, 2 low, 3 unbalanced, 4 balanced.
    var status: Int?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        // All HRV millisecond values use scale 128.
        weeklyAverageMs = m.scaled(0, scale: 128)
        lastNightAverageMs = m.scaled(1, scale: 128)
        lastNightFiveMinuteHighMs = m.scaled(2, scale: 128)
        baselineLowUpperMs = m.scaled(3, scale: 128)
        baselineBalancedLowerMs = m.scaled(4, scale: 128)
        baselineBalancedUpperMs = m.scaled(5, scale: 128)
        status = m.enumValue(6)
    }

    var statusLabel: String? {
        switch status {
        case 1: "Poor"
        case 2: "Low"
        case 3: "Unbalanced"
        case 4: "Balanced"
        default: nil
        }
    }
}

/// A single HRV reading, RMSSD in milliseconds.
nonisolated struct FITHRVValue {
    var timestamp: Date?
    var valueMs: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        valueMs = m.scaled(0, scale: 128)
    }
}

/// Body Battery. One message covers a span, with `level` holding a reading per interval,
/// so timestamps are reconstructed as `timestamp + index * processingInterval`.
///
/// This is one of the Garmin metrics that never reaches Apple Health at all.
nonisolated struct FITBodyBattery {
    var timestamp: Date?
    var processingIntervalSeconds: Double?
    var levels: [Double]?
    var charged: [Double]?
    var uncharged: [Double]?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        processingIntervalSeconds = m.raw(0)
        levels = m[1]?.arrayValue
        charged = m[2]?.arrayValue
        uncharged = m[3]?.arrayValue
    }

    /// Expand into timestamped readings.
    func samples() -> [(date: Date, level: Double)] {
        guard let timestamp, let levels, let interval = processingIntervalSeconds, interval > 0 else {
            return []
        }
        return levels.enumerated().compactMap { index, level in
            // Garmin uses negative values as "no reading".
            guard level >= 0, level <= 100 else { return nil }
            return (timestamp.addingTimeInterval(Double(index) * interval), level)
        }
    }
}

/// All-day stress, in the same interval-array shape as Body Battery.
nonisolated struct FITStressData {
    var timestamp: Date?
    var processingIntervalSeconds: Double?
    var levels: [Double]?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        processingIntervalSeconds = m.raw(0)
        levels = m[1]?.arrayValue
    }

    func samples() -> [(date: Date, level: Double)] {
        guard let timestamp, let levels, let interval = processingIntervalSeconds, interval > 0 else {
            return []
        }
        return levels.enumerated().compactMap { index, level in
            guard level >= 0, level <= 100 else { return nil }
            return (timestamp.addingTimeInterval(Double(index) * interval), level)
        }
    }
}

/// A discrete stress reading. Garmin writes a negative value when it could not measure.
nonisolated struct FITStressLevel {
    var value: Double?
    var time: Date?

    init(_ m: FITMessage) {
        value = m.raw(0)
        time = m.date(1)
    }

    var isValid: Bool { (value ?? -1) >= 0 }
}

nonisolated struct FITSpo2 {
    var timestamp: Date?
    var percent: Double?
    var confidence: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        percent = m.raw(0)
        confidence = m.raw(1)
    }
}

nonisolated struct FITRespirationRate {
    var timestamp: Date?
    var breathsPerMinute: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        breathsPerMinute = m.scaled(0, scale: 100)
    }

    /// Garmin writes negative sentinels when a reading could not be taken.
    var isValid: Bool { (breathsPerMinute ?? -1) > 0 }
}

/// VO2 max, as estimated by the device.
nonisolated struct FITMaxMetData {
    var updateTime: Date?
    var vo2Max: Double?
    var sport: Int?

    init(_ m: FITMessage) {
        updateTime = m.date(0)
        vo2Max = m.scaled(2, scale: 10)
        sport = m.enumValue(5)
    }
}

/// Heart-rate and power zone boundaries the device was using, plus the athlete's own
/// max, resting and threshold heart rate as configured on the watch. This is a genuinely
/// useful find: it lets the app seed the athlete profile from the device's own settings
/// rather than a population estimate.
nonisolated struct FITTimeInZone {
    var timestamp: Date?
    var referenceMessage: Int?
    var timeInHeartRateZoneSeconds: [Double]?
    var timeInPowerZoneSeconds: [Double]?
    var heartRateZoneHighBoundaries: [Double]?
    var powerZoneHighBoundaries: [Double]?
    var maxHeartRate: Double?
    var restingHeartRate: Double?
    var thresholdHeartRate: Double?
    var functionalThresholdPower: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        referenceMessage = m.enumValue(0)
        timeInHeartRateZoneSeconds = m.scaledArray(2, scale: 1000)
        timeInPowerZoneSeconds = m.scaledArray(5, scale: 1000)
        heartRateZoneHighBoundaries = m[6]?.arrayValue
        powerZoneHighBoundaries = m[9]?.arrayValue
        maxHeartRate = m.raw(11)
        restingHeartRate = m.raw(12)
        thresholdHeartRate = m.raw(13)
        functionalThresholdPower = m.raw(15)
    }
}

/// The device's stored user profile, another source of real anchors.
nonisolated struct FITUserProfile {
    /// 0 female, 1 male.
    var gender: Int?
    var age: Double?
    var heightMeters: Double?
    var weightKg: Double?
    var restingHeartRate: Double?
    var defaultMaxHeartRate: Double?
    var defaultMaxRunningHeartRate: Double?

    init(_ m: FITMessage) {
        // Field 0 is friendlyName, so the numeric fields start at 1.
        gender = m.enumValue(1)
        age = m.raw(2)
        heightMeters = m.scaled(3, scale: 100)
        weightKg = m.scaled(4, scale: 10)
        restingHeartRate = m.raw(8)
        defaultMaxRunningHeartRate = m.raw(9)
        defaultMaxHeartRate = m.raw(11)
    }

    var athleteSex: AthleteSex? {
        switch gender {
        case 0: .female
        case 1: .male
        default: nil
        }
    }
}

nonisolated struct FITWeightScale {
    var timestamp: Date?
    var weightKg: Double?
    var percentFat: Double?
    var boneMassKg: Double?
    var muscleMassKg: Double?

    init(_ m: FITMessage) {
        timestamp = m.date(253)
        weightKg = m.scaled(0, scale: 100)
        percentFat = m.scaled(1, scale: 100)
        // Field 2 is percentHydration and 3 is visceralFatMass, so bone and muscle mass
        // are 4 and 5 rather than the adjacent numbers they look like they should be.
        boneMassKg = m.scaled(4, scale: 100)
        muscleMassKg = m.scaled(5, scale: 100)
    }
}

// MARK: - Sport mapping

/// Map the FIT `sport` and `subSport` enums onto the app's `WorkoutSport`.
///
/// `subSport` carries the distinction that matters most for analysis: a treadmill run has
/// no usable GPS pace and no grade, a trail run needs grade adjustment, an indoor ride
/// has no wind. Reading it is what makes the downstream analysis correct rather than
/// merely populated.
nonisolated enum FITSportMapper {

    /// FIT sport enum values used below (from the Global Profile).
    private enum Sport: Int {
        case generic = 0, running = 1, cycling = 2, transition = 3, fitnessEquipment = 4
        case swimming = 5, basketball = 6, soccer = 7, tennis = 8, americanFootball = 9
        case training = 10, walking = 11, crossCountrySkiing = 12, alpineSkiing = 13
        case snowboarding = 14, rowing = 15, mountaineering = 16, hiking = 17
        case multisport = 18, paddling = 19, flying = 20, eBiking = 21
        case golf = 25, horsebackRiding = 27, inlineSkating = 30, rockClimbing = 31
        case sailing = 32, iceSkating = 33, snowshoeing = 35
        case standUpPaddleboarding = 37, surfing = 38, kayaking = 41
        case windsurfing = 43, kitesurfing = 44, tactical = 45, jumpmaster = 46
        case boxing = 47, floorClimbing = 48
        case racket = 64, waterTubing = 76, wakesurfing = 77
    }

    /// FIT subSport enum values used below.
    private enum SubSport: Int {
        case generic = 0, treadmill = 1, street = 2, trail = 3, track = 4
        case spin = 5, indoorCycling = 6, road = 7, mountain = 8, downhill = 9
        case recumbent = 10, cyclocross = 11, handCycling = 12, trackCycling = 13
        case indoorRowing = 14, elliptical = 15, stairClimbing = 16
        case lapSwimming = 17, openWater = 18, flexibilityTraining = 19
        case strengthTraining = 20, cardioTraining = 26, indoorWalking = 27
        case yoga = 43, pilates = 44, indoorRunning = 45, gravelCycling = 46
        case obstacle = 59, breathing = 62, ultra = 67, indoorClimbing = 68
        case bouldering = 69, hiit = 70, amrap = 73, emom = 74, tabata = 75
        case pickleball = 84, padel = 85, squash = 94, badminton = 95
    }

    static func sport(fitSport: Int?, fitSubSport: Int?) -> WorkoutSport {
        let sub = fitSubSport.flatMap(SubSport.init(rawValue:))

        switch fitSport.flatMap(Sport.init(rawValue:)) {
        case .running:
            switch sub {
            case .treadmill, .indoorRunning: return .treadmillRun
            case .trail, .ultra:             return .trailRun
            case .track:                     return .track
            default:                         return .run
            }
        case .cycling, .eBiking:
            switch sub {
            case .spin, .indoorCycling, .trackCycling: return .indoorRide
            case .mountain, .downhill, .cyclocross:    return .mountainBike
            case .gravelCycling:                       return .gravelRide
            case .handCycling:                         return .handCycle
            default:                                   return .ride
            }
        case .walking:
            return .walk
        case .hiking, .mountaineering, .snowshoeing:
            return .hike
        case .swimming:
            switch sub {
            case .openWater: return .openWaterSwim
            default:         return .poolSwim
            }
        case .rowing:
            return sub == .indoorRowing ? .indoorRow : .row
        case .paddling, .standUpPaddleboarding, .kayaking:
            return .paddle
        case .surfing, .windsurfing, .kitesurfing, .wakesurfing:
            return .surf
        case .training, .tactical:
            // A generic "training" activity is disambiguated entirely by subSport.
            switch sub {
            case .strengthTraining:      return .strengthTraining
            case .cardioTraining:        return .crossTraining
            case .flexibilityTraining:   return .flexibility
            case .yoga:                  return .yoga
            case .pilates:               return .pilates
            case .hiit, .amrap, .emom, .tabata: return .hiit
            case .breathing:             return .mindAndBody
            case .indoorWalking:         return .walk
            default:                     return .functionalStrength
            }
        case .fitnessEquipment:
            switch sub {
            case .elliptical:    return .elliptical
            case .stairClimbing: return .stairClimber
            case .indoorRowing:  return .indoorRow
            case .indoorCycling: return .indoorRide
            case .treadmill:     return .treadmillRun
            default:             return .crossTraining
            }
        case .rockClimbing:
            return .climbing
        case .boxing:
            return .boxing
        case .basketball, .soccer, .americanFootball:
            return .teamSport
        case .tennis, .racket:
            return .racquetSport
        case .alpineSkiing, .snowboarding, .crossCountrySkiing:
            return .snowSport
        case .iceSkating, .inlineSkating:
            return .skateSport
        case .golf:
            return .golf
        case .floorClimbing:
            return .stairClimber
        default:
            // Fall back on subSport when the sport is generic, which older devices do.
            switch sub {
            case .strengthTraining: return .strengthTraining
            case .yoga:             return .yoga
            case .pilates:          return .pilates
            case .treadmill:        return .treadmillRun
            case .trail:            return .trailRun
            case .elliptical:       return .elliptical
            case .hiit:             return .hiit
            default:                return .other
            }
        }
    }

    /// Whether the FIT sub-sport says this session was indoors.
    static func isIndoor(fitSubSport: Int?) -> Bool? {
        guard let sub = fitSubSport.flatMap(SubSport.init(rawValue:)) else { return nil }
        switch sub {
        case .treadmill, .indoorRunning, .spin, .indoorCycling, .trackCycling,
             .indoorRowing, .elliptical, .stairClimbing, .indoorWalking,
             .lapSwimming, .indoorClimbing:
            return true
        case .street, .trail, .track, .road, .mountain, .downhill, .gravelCycling,
             .openWater, .obstacle:
            return false
        default:
            return nil
        }
    }
}
