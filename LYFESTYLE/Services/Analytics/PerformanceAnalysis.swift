//
//  PerformanceAnalysis.swift
//  LYFESTYL
//
//  Endurance performance: what the running and riding data says about fitness, and how it
//  is moving.
//
//  The central idea is that raw pace is a bad progress signal, because it confounds fitness
//  with effort and terrain. A faster run might mean you are fitter, or that you tried
//  harder, or that it was flatter. The measures here control for that:
//
//    EFFICIENCY FACTOR   output per heartbeat. Rising at a given effort is the classic sign
//                        of improving aerobic fitness, and it is effort-independent.
//    DECOUPLING          how much output per heartbeat faded within a session, which is
//                        aerobic durability rather than top-end speed.
//    MEAN-MAXIMAL CURVE  the best sustained pace or power for each duration, which is the
//                        honest way to compare a 5k effort against a 5k effort.
//    CRITICAL SPEED      the two-parameter hyperbolic model, which separates sustainable
//                        aerobic capability from finite anaerobic reserve.
//
//  Every prediction states the model it came from, because a race-time estimate from a
//  formula is not a measurement.
//

import Foundation

// MARK: - Mean-maximal curve

/// The best sustained effort for each of a set of durations, computed from a session's own
/// samples. This is what makes "was that actually a good 20 minutes" answerable.
nonisolated struct MeanMaximalCurve: Sendable {
    /// Duration in seconds mapped to the best rolling mean achieved over that duration.
    var best: [Int: Double]
    /// Which metric the values are in.
    var metric: Metric

    enum Metric: String, Sendable {
        case powerWatts
        case speedMps

        var label: String {
            switch self {
            case .powerWatts: "power"
            case .speedMps:   "speed"
            }
        }
    }

    /// The durations sampled. Chosen to span the neuromuscular through aerobic range and to
    /// include the classic test durations.
    static let durations: [Int] = [5, 15, 30, 60, 120, 300, 480, 600, 1200, 1800, 3600, 5400]

    func value(for duration: Int) -> Double? { best[duration] }

    /// The durations that actually have a value, ascending.
    var populatedDurations: [Int] {
        best.keys.sorted()
    }

    /// Compute from a series. Requires an evenly resampled series, which is done here.
    static func compute(_ series: MetricSeries, metric: Metric) -> MeanMaximalCurve? {
        guard series.count >= 5, series.duration >= 10 else { return nil }
        let uniform = series.resampled(everySeconds: 1)
        guard uniform.count >= 5 else { return nil }
        let values = uniform.values

        // Prefix sums make every window mean O(1), so the whole curve is one pass per
        // duration rather than a nested scan.
        var prefix: [Double] = [0]
        prefix.reserveCapacity(values.count + 1)
        for value in values { prefix.append(prefix[prefix.count - 1] + value) }

        var best: [Int: Double] = [:]
        for duration in durations where duration <= values.count {
            var maximum = -Double.infinity
            for start in 0...(values.count - duration) {
                let mean = (prefix[start + duration] - prefix[start]) / Double(duration)
                if mean > maximum { maximum = mean }
            }
            if maximum.isFinite, maximum > 0 { best[duration] = maximum }
        }
        return best.isEmpty ? nil : MeanMaximalCurve(best: best, metric: metric)
    }

    /// Combine curves from many sessions, keeping the best at each duration.
    static func combine(_ curves: [MeanMaximalCurve], metric: Metric) -> MeanMaximalCurve? {
        let matching = curves.filter { $0.metric == metric }
        guard !matching.isEmpty else { return nil }
        var best: [Int: Double] = [:]
        for curve in matching {
            for (duration, value) in curve.best {
                best[duration] = max(best[duration] ?? 0, value)
            }
        }
        return best.isEmpty ? nil : MeanMaximalCurve(best: best, metric: metric)
    }
}

// MARK: - Critical speed and power

/// The two-parameter critical-power model, fitted to a set of maximal efforts.
///
/// The model is
///
///     distance = CS x time + D'
///
/// where CS (critical speed, m/s) is the highest intensity sustainable without drawing on a
/// finite reserve, and D' (in meters) is that reserve. In the power form the same algebra
/// gives CP in watts and W' in joules.
///
/// Fitted by ordinary least squares on distance against time, which is the standard linear
/// form and is well conditioned as long as the efforts span a decent range of durations.
nonisolated struct CriticalIntensity: Sendable {
    /// Critical speed in meters per second, or critical power in watts.
    var critical: Double
    /// The finite reserve: D' in meters, or W' in joules.
    var reserve: Double
    /// Efforts the fit used.
    var effortCount: Int
    /// Coefficient of determination of the linear fit.
    var rSquared: Double
    var metric: MeanMaximalCurve.Metric

    /// The model is only meaningful when the efforts span a real range of durations. Fitting
    /// two efforts thirty seconds apart yields a number with no physiological content.
    var isWellConditioned: Bool { effortCount >= 3 && rSquared > 0.9 }

    /// Predicted time to cover a distance, inverting the model.
    func predictedTime(forDistance meters: Double) -> Double? {
        guard metric == .speedMps, critical > 0, meters > reserve else { return nil }
        return (meters - reserve) / critical
    }

    /// Predicted sustainable intensity for a duration.
    func predictedIntensity(forDuration seconds: Double) -> Double? {
        guard seconds > 0, critical > 0 else { return nil }
        return critical + reserve / seconds
    }

    /// Fit from a mean-maximal curve, using efforts between two and twenty minutes, the
    /// range the model is conventionally fitted over.
    static func fit(from curve: MeanMaximalCurve) -> CriticalIntensity? {
        let usable = curve.best
            .filter { $0.key >= 120 && $0.key <= 1200 }
            .sorted { $0.key < $1.key }
        guard usable.count >= 3 else { return nil }

        // distance = intensity x time, so regress distance on time.
        let times = usable.map { Double($0.key) }
        let distances = usable.map { Double($0.key) * $0.value }
        guard let regression = Stats.linearRegression(x: times, y: distances),
              regression.slope > 0 else { return nil }

        return CriticalIntensity(
            critical: regression.slope,
            reserve: max(0, regression.intercept),
            effortCount: usable.count,
            rSquared: regression.rSquared,
            metric: curve.metric
        )
    }
}

// MARK: - Race prediction

nonisolated enum RacePrediction {

    /// Riegel's endurance formula:
    ///
    ///     T2 = T1 x (D2 / D1)^1.06
    ///
    /// Peter Riegel (1977, 1981), "Athletic Records and Human Endurance". The exponent 1.06
    /// is the widely cited value fitted across distance-running records; published estimates
    /// range from about 1.06 to 1.08 and it drifts upward for very long distances.
    ///
    /// Reliable for extrapolations within roughly a factor of four in distance. Predicting a
    /// marathon from a 5k is outside that and the prediction is flagged accordingly.
    static let riegelExponent = 1.06

    static func riegel(
        knownTimeSeconds: Double,
        knownDistanceMeters: Double,
        targetDistanceMeters: Double
    ) -> Double? {
        guard knownTimeSeconds > 0, knownDistanceMeters > 0, targetDistanceMeters > 0 else {
            return nil
        }
        return knownTimeSeconds * pow(targetDistanceMeters / knownDistanceMeters, riegelExponent)
    }

    /// How far the extrapolation stretches, as a distance ratio. Above about four, treat the
    /// prediction as indicative only.
    static func extrapolationFactor(from: Double, to: Double) -> Double {
        guard from > 0, to > 0 else { return .infinity }
        return max(to / from, from / to)
    }

    static let reliableExtrapolationLimit = 4.0

    /// Standard race distances in meters.
    static let standardDistances: [(name: String, meters: Double)] = [
        ("1 mile", 1609.344),
        ("5K", 5000),
        ("10K", 10000),
        ("Half marathon", 21097.5),
        ("Marathon", 42195),
    ]

    /// A prediction with its provenance attached.
    nonisolated struct Prediction: Identifiable, Hashable, Sendable {
        var distanceName: String
        var distanceMeters: Double
        var predictedSeconds: Double
        /// The effort the prediction was extrapolated from.
        var basedOnDistanceMeters: Double
        var basedOnSeconds: Double
        var basedOnDate: Date
        var extrapolationFactor: Double

        var id: String { distanceName }

        var isReliable: Bool { extrapolationFactor <= RacePrediction.reliableExtrapolationLimit }

        var pacePerKm: Double { predictedSeconds / (distanceMeters / 1000) }
    }
}

// MARK: - VO2 max estimation

nonisolated enum VO2MaxEstimate {

    /// Uth, Sorensen, Overgaard and Pedersen (2004), Eur J Appl Physiol 91:111-115:
    ///
    ///     VO2max = 15.3 x (HRmax / HRrest)
    ///
    /// Crude but genuinely useful because it needs only two numbers the app already has.
    /// It is a population regression, not a measurement, and is labelled as an estimate
    /// everywhere it appears.
    static func fromHeartRateRatio(maxHeartRate: Double, restingHeartRate: Double) -> Double? {
        guard restingHeartRate > 20, maxHeartRate > restingHeartRate else { return nil }
        let value = 15.3 * (maxHeartRate / restingHeartRate)
        // Outside this range the formula has left its fitted domain.
        guard value > 15, value < 90 else { return nil }
        return value
    }

    /// Daniels and Gilbert's VDOT, from "Oxygen Power" and Daniels' Running Formula.
    ///
    /// Two equations combine. The oxygen cost of running at velocity v (meters per minute):
    ///
    ///     VO2 = -4.60 + 0.182258 v + 0.000104 v^2
    ///
    /// and the fraction of VO2max sustainable for a duration t (minutes):
    ///
    ///     %VO2max = 0.8 + 0.1894393 e^(-0.012778 t) + 0.2989558 e^(-0.1932605 t)
    ///
    /// VDOT is their quotient. It is a pseudo-VO2max: a single number summarising running
    /// fitness that happens to share units with VO2 max, and it is the basis of Daniels'
    /// training paces.
    static func vdot(distanceMeters: Double, timeSeconds: Double) -> Double? {
        guard distanceMeters > 400, timeSeconds > 90 else { return nil }
        let minutes = timeSeconds / 60
        let velocity = distanceMeters / minutes            // meters per minute

        let oxygenCost = -4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity
        let fraction = 0.8
            + 0.1894393 * exp(-0.012778 * minutes)
            + 0.2989558 * exp(-0.1932605 * minutes)
        guard fraction > 0.3, oxygenCost > 0 else { return nil }
        let value = oxygenCost / fraction
        guard value > 15, value < 90 else { return nil }
        return value
    }

    /// The velocity a given VDOT sustains for a duration, inverting the pair numerically.
    /// Used to translate a VDOT back into training paces.
    static func velocity(forVDOT vdot: Double, minutes: Double) -> Double? {
        guard vdot > 15, minutes > 1 else { return nil }
        let fraction = 0.8
            + 0.1894393 * exp(-0.012778 * minutes)
            + 0.2989558 * exp(-0.1932605 * minutes)
        let targetCost = vdot * fraction
        // Solve -4.60 + 0.182258 v + 0.000104 v^2 = targetCost for v > 0.
        let a = 0.000104, b = 0.182258, c = -4.60 - targetCost
        let discriminant = b * b - 4 * a * c
        guard discriminant > 0 else { return nil }
        let v = (-b + sqrt(discriminant)) / (2 * a)
        return v > 0 ? v : nil
    }
}

// MARK: - Personal bests over distance

/// The fastest recorded time at or beyond a standard distance.
nonisolated struct DistanceBest: Identifiable, Hashable, Sendable {
    var distanceName: String
    var distanceMeters: Double
    var timeSeconds: Double
    var actualDistanceMeters: Double
    var date: Date
    var workoutID: String
    var sport: WorkoutSport

    var id: String { "\(distanceName)-\(workoutID)" }

    var pacePerKm: Double { timeSeconds / (actualDistanceMeters / 1000) }

    /// Whether the effort was close enough to the nominal distance to count as a time at it.
    /// A 12 kilometer run is not a 10k time, so anything beyond ten percent over is treated
    /// as an approximation and labelled.
    var isCloseToNominal: Bool {
        actualDistanceMeters <= distanceMeters * 1.10
    }
}

// MARK: - Analysis

nonisolated enum PerformanceAnalysis {

    /// Efficiency factor over time for one discipline, which is the cleanest available
    /// fitness signal that does not depend on how hard the session was.
    ///
    /// Only steady sessions of a reasonable length are used: efficiency factor from a
    /// twelve-minute interval session is noise, because the metric assumes a broadly
    /// continuous effort.
    static func efficiencySeries(
        workouts: [UnifiedWorkout],
        discipline: WorkoutSport.Discipline,
        minimumSeconds: Double = 1800
    ) -> [(date: Date, value: Double)] {
        workouts
            .filter { $0.discipline == discipline && $0.movingSeconds >= minimumSeconds }
            .compactMap { workout -> (Date, Double)? in
                guard let value = workout.efficiencyFactor else { return nil }
                return (workout.start, value)
            }
            .sorted { $0.0 < $1.0 }
    }

    /// Trend in efficiency factor, robustly. Returns nil until there is enough to say.
    static func efficiencyTrend(
        workouts: [UnifiedWorkout],
        discipline: WorkoutSport.Discipline
    ) -> (test: Stats.TrendTest, changePercent: Double)? {
        let series = efficiencySeries(workouts: workouts, discipline: discipline)
        let values = series.map(\.value)
        guard values.count >= 8, let test = Stats.mannKendall(values) else { return nil }
        guard let first = values.first, first > 0, let last = values.last else { return nil }
        // Compare robust fitted endpoints rather than raw first and last, so one outlying
        // session cannot manufacture a change.
        guard let fit = Stats.theilSenTrend(values) else { return nil }
        let start = fit.intercept
        let end = fit.intercept + fit.slope * Double(values.count - 1)
        guard start > 0 else { return nil }
        _ = (first, last)
        return (test, (end - start) / start * 100)
    }

    /// Decoupling over time. A falling decoupling percentage at similar intensity means
    /// aerobic durability is improving.
    static func decouplingSeries(
        workouts: [UnifiedWorkout],
        discipline: WorkoutSport.Discipline? = nil
    ) -> [(date: Date, value: Double)] {
        workouts
            .filter { discipline == nil || $0.discipline == discipline }
            .compactMap { workout -> (Date, Double)? in
                guard let value = workout.decouplingPercent else { return nil }
                return (workout.start, value)
            }
            .sorted { $0.0 < $1.0 }
    }

    /// Personal bests at each standard distance, from sessions long enough to contain them.
    ///
    /// Uses the session's own cumulative-distance and time series where available, so a
    /// 5 kilometer split inside a 10 kilometer run counts. Without a series, the whole
    /// session is considered only when its distance is close to the nominal one.
    static func distanceBests(workouts: [UnifiedWorkout]) -> [DistanceBest] {
        var best: [String: DistanceBest] = [:]

        for workout in workouts where workout.discipline == .running {
            guard let total = workout.distanceMeters, total > 400 else { continue }

            for (name, nominal) in RacePrediction.standardDistances where total >= nominal * 0.99 {
                var candidate: DistanceBest?

                if let distanceSeries = workout.distanceSeries, distanceSeries.count >= 10 {
                    // Fastest window covering the nominal distance, by two pointers over the
                    // cumulative-distance series.
                    if let fastest = fastestSplit(distanceSeries, nominalMeters: nominal) {
                        candidate = DistanceBest(
                            distanceName: name,
                            distanceMeters: nominal,
                            timeSeconds: fastest,
                            actualDistanceMeters: nominal,
                            date: workout.start,
                            workoutID: workout.id,
                            sport: workout.sport
                        )
                    }
                }
                if candidate == nil, total <= nominal * 1.10, workout.movingSeconds > 0 {
                    candidate = DistanceBest(
                        distanceName: name,
                        distanceMeters: nominal,
                        // Scale the whole-session time to the nominal distance. Approximate,
                        // and flagged by `isCloseToNominal`.
                        timeSeconds: workout.movingSeconds * (nominal / total),
                        actualDistanceMeters: total,
                        date: workout.start,
                        workoutID: workout.id,
                        sport: workout.sport
                    )
                }

                guard let candidate else { continue }
                if let existing = best[name], existing.timeSeconds <= candidate.timeSeconds {
                    continue
                }
                best[name] = candidate
            }
        }

        return RacePrediction.standardDistances.compactMap { best[$0.name] }
    }

    /// The fastest time to cover `nominalMeters` anywhere inside a cumulative-distance
    /// series. Two pointers, so it is linear in the number of samples.
    private static func fastestSplit(_ distanceSeries: MetricSeries, nominalMeters: Double) -> Double? {
        let offsets = distanceSeries.offsets
        let distances = distanceSeries.values
        guard let total = distances.last, total >= nominalMeters else { return nil }

        var bestTime = Double.infinity
        var start = 0
        for end in distances.indices {
            // Advance `start` while the window still covers the distance.
            while start < end, distances[end] - distances[start + 1] >= nominalMeters {
                start += 1
            }
            guard distances[end] - distances[start] >= nominalMeters else { continue }
            let time = offsets[end] - offsets[start]
            if time > 0, time < bestTime { bestTime = time }
        }
        return bestTime.isFinite ? bestTime : nil
    }

    /// Race predictions from the strongest recent effort.
    static func predictions(
        from bests: [DistanceBest],
        now: Date = Date(),
        withinDays: Int = 120
    ) -> [RacePrediction.Prediction] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -withinDays, to: now) else {
            return []
        }
        // Base the prediction on the best recent effort, preferring longer efforts because
        // they extrapolate more reliably in both directions.
        let recent = bests.filter { $0.date >= cutoff && $0.isCloseToNominal }
        guard let base = recent.max(by: { $0.distanceMeters < $1.distanceMeters }) else { return [] }

        return RacePrediction.standardDistances.compactMap { name, meters in
            guard abs(meters - base.distanceMeters) > 1 else { return nil }
            guard let seconds = RacePrediction.riegel(
                knownTimeSeconds: base.timeSeconds,
                knownDistanceMeters: base.distanceMeters,
                targetDistanceMeters: meters
            ) else { return nil }
            return RacePrediction.Prediction(
                distanceName: name,
                distanceMeters: meters,
                predictedSeconds: seconds,
                basedOnDistanceMeters: base.distanceMeters,
                basedOnSeconds: base.timeSeconds,
                basedOnDate: base.date,
                extrapolationFactor: RacePrediction.extrapolationFactor(
                    from: base.distanceMeters, to: meters
                )
            )
        }
    }

    /// Best VDOT from recent efforts, which doubles as a running-fitness index.
    static func bestVDOT(from bests: [DistanceBest], now: Date = Date(), withinDays: Int = 120) -> (value: Double, from: DistanceBest)? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -withinDays, to: now) else {
            return nil
        }
        let candidates = bests
            .filter { $0.date >= cutoff && $0.isCloseToNominal }
            .compactMap { best -> (Double, DistanceBest)? in
                guard let value = VO2MaxEstimate.vdot(
                    distanceMeters: best.actualDistanceMeters,
                    timeSeconds: best.timeSeconds
                ) else { return nil }
                return (value, best)
            }
        return candidates.max { $0.0 < $1.0 }
    }

    /// Build the combined mean-maximal curve across sessions in a discipline.
    static func meanMaximalCurve(
        workouts: [UnifiedWorkout],
        discipline: WorkoutSport.Discipline
    ) -> MeanMaximalCurve? {
        let metric: MeanMaximalCurve.Metric = discipline == .cycling ? .powerWatts : .speedMps
        let curves = workouts
            .filter { $0.discipline == discipline }
            .compactMap { workout -> MeanMaximalCurve? in
                let series = metric == .powerWatts ? workout.powerSeries : workout.speedSeries
                guard let series else { return nil }
                return MeanMaximalCurve.compute(series, metric: metric)
            }
        return MeanMaximalCurve.combine(curves, metric: metric)
    }

    /// Volume rollup for a discipline over a window.
    nonisolated struct DisciplineSummary: Identifiable, Hashable, Sendable {
        var discipline: WorkoutSport.Discipline
        var sessionCount: Int
        var totalSeconds: Double
        var totalDistanceMeters: Double
        var totalElevationMeters: Double
        var averagePaceSecondsPerKm: Double?
        var averageHeartRate: Double?

        var id: String { discipline.rawValue }
    }

    static func disciplineSummaries(
        workouts: [UnifiedWorkout],
        windowDays: Int = 28,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DisciplineSummary] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else {
            return []
        }
        let relevant = workouts.filter { $0.day >= windowStart }
        let grouped = Dictionary(grouping: relevant) { $0.discipline }

        return grouped.compactMap { discipline, sessions -> DisciplineSummary? in
            guard discipline != .none else { return nil }
            let seconds = sessions.reduce(0) { $0 + $1.movingSeconds }
            let distance = sessions.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) }
            return DisciplineSummary(
                discipline: discipline,
                sessionCount: sessions.count,
                totalSeconds: seconds,
                totalDistanceMeters: distance,
                totalElevationMeters: sessions.reduce(0.0) { $0 + ($1.elevationGainMeters ?? 0) },
                averagePaceSecondsPerKm: distance > 500 ? seconds / (distance / 1000) : nil,
                averageHeartRate: Stats.mean(sessions.compactMap(\.averageHeartRate))
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
    }
}
