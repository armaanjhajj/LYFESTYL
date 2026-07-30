//
//  UnifiedWorkout.swift
//  LYFESTYL
//
//  ONE canonical training session, whatever it came from. A Garmin trail run read
//  through Apple Health, a Hevy lifting session pulled from its REST API, and a
//  session logged by hand in LYFESTYL all normalize into this, which is what makes
//  a single unified history (and a single set of trends) possible.
//
//  Canonical units, always, so no analysis has to ask: SECONDS, METERS,
//  METERS PER SECOND, KILOGRAMS, WATTS, BEATS PER MINUTE, KILOCALORIES, CELSIUS.
//  Conversion happens at the presentation layer only.
//
//  Honesty rules that shape this type:
//    - Every metric is optional. A run without a heart-rate strap has no average
//      heart rate, and that stays nil rather than becoming a zero that would drag
//      down every average it touches.
//    - Nothing derived from the athlete's changeable profile (training load, zones,
//      intensity) is stored. Those are computed on demand, so correcting a max
//      heart rate retroactively fixes the whole history instead of leaving stale
//      numbers behind.
//    - Metrics that depend only on the session's own samples (normalized power,
//      aerobic decoupling) ARE cached, because they can never go stale.
//

import Foundation

// MARK: - Sampled series

/// A numeric series sampled across a workout. `offsets` are seconds elapsed from
/// the workout start and are strictly increasing; `values` is the same length.
///
/// Series are downsampled at ingest (see `Downsampler`) so a three-hour ride costs
/// kilobytes, not megabytes, while keeping enough resolution for drift and
/// decoupling analysis.
struct MetricSeries: Codable, Hashable, Sendable {
    var offsets: [Double]
    var values: [Double]

    init(offsets: [Double] = [], values: [Double] = []) {
        // Defend the invariant: a mismatched pair would silently corrupt every
        // downstream calculation, so truncate to the shorter of the two.
        let n = min(offsets.count, values.count)
        self.offsets = Array(offsets.prefix(n))
        self.values = Array(values.prefix(n))
    }

    var count: Int { values.count }
    var isEmpty: Bool { values.isEmpty }

    var duration: Double {
        guard let first = offsets.first, let last = offsets.last else { return 0 }
        return last - first
    }

    var mean: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var maximum: Double? { values.max() }
    var minimum: Double? { values.min() }

    /// The samples falling inside a half-open offset window.
    func slice(from: Double, to: Double) -> MetricSeries {
        var o: [Double] = []
        var v: [Double] = []
        for (i, offset) in offsets.enumerated() where offset >= from && offset < to {
            o.append(offset)
            v.append(values[i])
        }
        return MetricSeries(offsets: o, values: v)
    }

    /// Mean over a window, nil when the window caught no samples.
    func mean(from: Double, to: Double) -> Double? {
        slice(from: from, to: to).mean
    }

    /// Resample onto a fixed grid by taking the mean of the samples inside each
    /// bucket, carrying the previous value forward across short gaps. Needed
    /// because rolling-window maths (normalized power, mean-maximal curves) assume
    /// an even sample spacing.
    func resampled(everySeconds step: Double) -> MetricSeries {
        guard let first = offsets.first, let last = offsets.last, step > 0, count > 1 else {
            return self
        }
        var o: [Double] = []
        var v: [Double] = []
        var cursor = first
        var index = 0
        var carried: Double?
        while cursor <= last {
            var bucket: [Double] = []
            while index < offsets.count, offsets[index] < cursor + step {
                bucket.append(values[index])
                index += 1
            }
            if bucket.isEmpty {
                // Short gap: hold the last known value. Long gaps are handled by
                // the caller trimming the series, we do not invent data beyond a
                // single step.
                if let carried {
                    o.append(cursor)
                    v.append(carried)
                }
            } else {
                let m = bucket.reduce(0, +) / Double(bucket.count)
                carried = m
                o.append(cursor)
                v.append(m)
            }
            cursor += step
        }
        return MetricSeries(offsets: o, values: v)
    }
}

// MARK: - Heart-rate zone occupancy

/// Seconds spent in each of the five classic heart-rate zones. Boundaries come
/// from the athlete profile, so this is always computed and never stored.
struct ZoneDistribution: Hashable, Sendable {
    /// Index 0 is zone 1 (easiest) through index 4 (zone 5).
    var seconds: [Double]

    static let zoneCount = 5

    init(seconds: [Double] = Array(repeating: 0, count: ZoneDistribution.zoneCount)) {
        var s = seconds
        while s.count < Self.zoneCount { s.append(0) }
        self.seconds = Array(s.prefix(Self.zoneCount))
    }

    var total: Double { seconds.reduce(0, +) }

    func fraction(zone: Int) -> Double {
        guard total > 0, zone >= 0, zone < Self.zoneCount else { return 0 }
        return seconds[zone] / total
    }

    /// Seconds at or below zone 2, the usual definition of easy aerobic work.
    var easySeconds: Double { seconds[0] + seconds[1] }
    /// Seconds in zone 4 and 5, the genuinely hard work.
    var hardSeconds: Double { seconds[3] + seconds[4] }
}

// MARK: - Route summary

/// A compact stand-in for a full GPS track: enough to draw a shape and describe
/// where a session happened, without storing thousands of coordinates.
struct RouteSummary: Codable, Hashable, Sendable {
    /// Downsampled coordinate pairs, latitude then longitude.
    var latitudes: [Double]
    var longitudes: [Double]
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    init(latitudes: [Double], longitudes: [Double]) {
        let n = min(latitudes.count, longitudes.count)
        let lats = Array(latitudes.prefix(n))
        let lons = Array(longitudes.prefix(n))
        self.latitudes = lats
        self.longitudes = lons
        self.minLatitude = lats.min() ?? 0
        self.maxLatitude = lats.max() ?? 0
        self.minLongitude = lons.min() ?? 0
        self.maxLongitude = lons.max() ?? 0
    }

    var isEmpty: Bool { latitudes.isEmpty }
    var pointCount: Int { latitudes.count }
}

// MARK: - The unified workout

struct UnifiedWorkout: Identifiable, Hashable, Codable, Sendable {

    // Identity and provenance
    /// `"<source>:<foreignID>"`, stable across syncs so an update rewrites in place.
    var id: String
    var origin: SourceRef
    /// Additional sources that described this same session and were merged away.
    /// Kept so the UI can say "Garmin and Hevy both saw this".
    var mergedSources: [SourceRef]

    var sport: WorkoutSport
    var title: String
    var notes: String?

    // Time
    var start: Date
    var end: Date
    /// Active/moving time in seconds. Falls back to elapsed when the source has no
    /// notion of pauses.
    var movingSeconds: Double
    /// Wall-clock seconds from start to end, pauses included.
    var elapsedSeconds: Double
    /// Whether the session was indoors, which suppresses pace and grade analysis.
    var isIndoor: Bool

    // Endurance metrics
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var averageSpeedMps: Double?
    var maxSpeedMps: Double?
    var averagePowerWatts: Double?
    var maxPowerWatts: Double?
    var averageCadence: Double?          // rpm for cycling, spm for running
    var averageStrideLengthMeters: Double?
    var averageGroundContactMs: Double?
    var averageVerticalOscillationCm: Double?
    var swimStrokeCount: Double?

    // Subjective and source-provided effort
    /// Session RPE on a 0 to 10 scale, when the user or the source recorded one.
    var perceivedEffort: Double?
    /// Apple's own effort score, where the watch estimated or the user rated one.
    var workoutEffortScore: Double?

    // Cached, sample-derived metrics. These depend only on this session's own
    // samples, never on the athlete profile, so they can be stored without ever
    // going stale.
    /// Normalized power in watts, per the 30-second rolling fourth-power method.
    var normalizedPowerWatts: Double?
    /// Aerobic decoupling percent across the session's steady portion.
    var decouplingPercent: Double?

    // Samples
    var heartRateSeries: MetricSeries?
    var speedSeries: MetricSeries?
    var powerSeries: MetricSeries?
    var cadenceSeries: MetricSeries?
    var altitudeSeries: MetricSeries?
    /// Cumulative distance in meters, used to compute grade-adjusted pace.
    var distanceSeries: MetricSeries?
    var route: RouteSummary?

    // Strength payload
    var strength: StrengthSession?

    /// The calendar day this session is filed under, for daily aggregation.
    var day: Date

    init(
        id: String,
        origin: SourceRef,
        mergedSources: [SourceRef] = [],
        sport: WorkoutSport,
        title: String,
        notes: String? = nil,
        start: Date,
        end: Date,
        movingSeconds: Double? = nil,
        isIndoor: Bool? = nil,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        averageSpeedMps: Double? = nil,
        maxSpeedMps: Double? = nil,
        averagePowerWatts: Double? = nil,
        maxPowerWatts: Double? = nil,
        averageCadence: Double? = nil,
        averageStrideLengthMeters: Double? = nil,
        averageGroundContactMs: Double? = nil,
        averageVerticalOscillationCm: Double? = nil,
        swimStrokeCount: Double? = nil,
        perceivedEffort: Double? = nil,
        workoutEffortScore: Double? = nil,
        normalizedPowerWatts: Double? = nil,
        decouplingPercent: Double? = nil,
        heartRateSeries: MetricSeries? = nil,
        speedSeries: MetricSeries? = nil,
        powerSeries: MetricSeries? = nil,
        cadenceSeries: MetricSeries? = nil,
        altitudeSeries: MetricSeries? = nil,
        distanceSeries: MetricSeries? = nil,
        route: RouteSummary? = nil,
        strength: StrengthSession? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.origin = origin
        self.mergedSources = mergedSources
        self.sport = sport
        self.title = title
        self.notes = notes
        self.start = start
        self.end = max(end, start)
        let elapsed = self.end.timeIntervalSince(start)
        self.elapsedSeconds = elapsed
        self.movingSeconds = movingSeconds ?? elapsed
        self.isIndoor = isIndoor ?? sport.isIndoorByNature
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageSpeedMps = averageSpeedMps
        self.maxSpeedMps = maxSpeedMps
        self.averagePowerWatts = averagePowerWatts
        self.maxPowerWatts = maxPowerWatts
        self.averageCadence = averageCadence
        self.averageStrideLengthMeters = averageStrideLengthMeters
        self.averageGroundContactMs = averageGroundContactMs
        self.averageVerticalOscillationCm = averageVerticalOscillationCm
        self.swimStrokeCount = swimStrokeCount
        self.perceivedEffort = perceivedEffort
        self.workoutEffortScore = workoutEffortScore
        self.normalizedPowerWatts = normalizedPowerWatts
        self.decouplingPercent = decouplingPercent
        self.heartRateSeries = heartRateSeries
        self.speedSeries = speedSeries
        self.powerSeries = powerSeries
        self.cadenceSeries = cadenceSeries
        self.altitudeSeries = altitudeSeries
        self.distanceSeries = distanceSeries
        self.route = route
        self.strength = strength
        self.day = calendar.startOfDay(for: start)
    }

    // MARK: - Derived, profile-independent

    var family: SportFamily { sport.family }
    var discipline: WorkoutSport.Discipline { sport.discipline }

    var durationMinutes: Double { movingSeconds / 60 }

    /// Average speed, preferring the source's own figure and falling back to
    /// distance over moving time. Nil when there is no distance at all.
    var effectiveSpeedMps: Double? {
        if let averageSpeedMps, averageSpeedMps > 0 { return averageSpeedMps }
        guard let distanceMeters, distanceMeters > 0, movingSeconds > 0 else { return nil }
        return distanceMeters / movingSeconds
    }

    /// Pace in seconds per kilometer. Only meaningful for distance sports.
    var paceSecondsPerKm: Double? {
        guard family.hasDistance, let speed = effectiveSpeedMps, speed > 0.1 else { return nil }
        return 1000 / speed
    }

    /// Pace in seconds per mile.
    var paceSecondsPerMile: Double? {
        paceSecondsPerKm.map { $0 * 1.609344 }
    }

    /// Efficiency factor: output per heartbeat. Rising over time at a fixed
    /// intensity is the classic sign of improving aerobic fitness. Uses normalized
    /// power when a power meter was present, otherwise speed.
    var efficiencyFactor: Double? {
        guard let hr = averageHeartRate, hr > 30 else { return nil }
        if let np = normalizedPowerWatts, np > 0 { return np / hr }
        guard let speed = effectiveSpeedMps, speed > 0.1 else { return nil }
        return speed / hr
    }

    /// Whether this session carries enough signal for load and intensity analysis.
    var hasIntensitySignal: Bool {
        averageHeartRate != nil || averagePowerWatts != nil
            || normalizedPowerWatts != nil || perceivedEffort != nil
    }

    /// Total volume load in kilograms for lifting sessions.
    var volumeLoadKg: Double? { strength?.volumeLoadKg }

    /// A short neutral line describing the session, in the caller's units.
    func metricsSummary(metric: Bool) -> String {
        var parts: [String] = []
        if let distanceMeters, distanceMeters > 0, family.hasDistance {
            parts.append(Formatting.distance(distanceMeters, metric: metric))
        }
        parts.append(Formatting.duration(movingSeconds))
        if let pace = paceSecondsPerKm, discipline == .running || discipline == .walking {
            parts.append(Formatting.pace(secondsPerKm: pace, metric: metric))
        } else if let speed = effectiveSpeedMps, discipline == .cycling {
            parts.append(Formatting.speed(speed, metric: metric))
        }
        if let strength {
            parts.append(strength.countSummary)
        }
        if let hr = averageHeartRate {
            parts.append("\(Int(hr.rounded())) bpm")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Downsampling

/// Keeps sampled series small enough to persist while preserving the shape the
/// analyses need. A cap of 720 points is one sample every five seconds for an
/// hour-long session, and every fifteen seconds for a three-hour ride, which is
/// well inside the resolution that drift and decoupling maths require.
enum Downsampler {
    static let maxPoints = 720

    /// Bucket-average a series down to at most `maxPoints` samples. Averaging
    /// rather than dropping samples means noisy heart-rate traces stay honest
    /// instead of picking up whichever value happened to land on a boundary.
    static func reduce(_ series: MetricSeries, to maxPoints: Int = Downsampler.maxPoints) -> MetricSeries {
        guard series.count > maxPoints, maxPoints > 1 else { return series }
        let bucketSize = Double(series.count) / Double(maxPoints)
        var offsets: [Double] = []
        var values: [Double] = []
        offsets.reserveCapacity(maxPoints)
        values.reserveCapacity(maxPoints)
        for bucket in 0..<maxPoints {
            let lo = Int((Double(bucket) * bucketSize).rounded(.down))
            let hi = min(series.count, Int((Double(bucket + 1) * bucketSize).rounded(.down)))
            guard lo < hi else { continue }
            var sumV = 0.0
            var sumO = 0.0
            for i in lo..<hi {
                sumV += series.values[i]
                sumO += series.offsets[i]
            }
            let n = Double(hi - lo)
            offsets.append(sumO / n)
            values.append(sumV / n)
        }
        return MetricSeries(offsets: offsets, values: values)
    }

    /// Thin a coordinate track by taking every nth point, keeping the endpoints.
    static func reduceRoute(latitudes: [Double], longitudes: [Double], to maxPoints: Int = 300) -> RouteSummary? {
        let n = min(latitudes.count, longitudes.count)
        guard n > 0 else { return nil }
        guard n > maxPoints else {
            return RouteSummary(latitudes: Array(latitudes.prefix(n)), longitudes: Array(longitudes.prefix(n)))
        }
        let stride = Double(n) / Double(maxPoints)
        var lats: [Double] = []
        var lons: [Double] = []
        var i = 0.0
        while Int(i) < n {
            lats.append(latitudes[Int(i)])
            lons.append(longitudes[Int(i)])
            i += stride
        }
        // Always keep the finish so the shape closes correctly.
        if let lastLat = latitudes.last, let lastLon = longitudes.last,
           lats.last != lastLat || lons.last != lastLon {
            lats.append(lastLat)
            lons.append(lastLon)
        }
        return RouteSummary(latitudes: lats, longitudes: lons)
    }
}
