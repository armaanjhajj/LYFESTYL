//
//  TrainingLoad.swift
//  LYFESTYL
//
//  Turning a session into a single number for how much it cost. This is the input to
//  the fitness/fatigue model, so getting it right and being clear about its
//  provenance matters more than having a number at all.
//
//  Every formula here is published, cited inline, and implemented exactly. Where the
//  literature does not actually publish a method (notably TrainingPeaks' Normalized
//  Graded Pace, whose grade-adjustment function has never been disclosed), the app
//  uses a peer-reviewed alternative and says so rather than pretending to reproduce
//  a proprietary metric.
//
//  Precedence, best signal first:
//    1. POWER + FTP           -> TSS, the reference implementation (Coggan)
//    2. PACE + threshold pace -> pace-based stress, grade-adjusted via Minetti
//    3. HEART RATE + profile  -> exponential TRIMP (Morton/Banister), scaled to the
//                                same 100-points-per-threshold-hour footing
//    4. SESSION RPE           -> Foster's RPE x minutes, the honest last resort
//
//  Each result carries the method that produced it and a confidence, so the UI never
//  presents an RPE-derived estimate with the same authority as a power file.
//

import Foundation

// MARK: - Result type

/// One session's training load, with full provenance.
nonisolated struct TrainingLoadResult: Hashable, Sendable {

    /// How the load was derived. Ordered by trustworthiness.
    enum Method: String, Codable, Hashable, Sendable, Comparable {
        /// Training Stress Score from a power meter against a known FTP.
        case powerTSS
        /// Pace-based stress against a known threshold pace, grade-adjusted.
        case paceStress
        /// Swim stress, using the cubic intensity term appropriate to water.
        case swimStress
        /// Exponential TRIMP from heart rate, rescaled to TSS-equivalent points.
        case heartRateTRIMP
        /// Zone-weighted TRIMP (Edwards), used when only zone occupancy is known.
        case zoneTRIMP
        /// Session RPE times duration (Foster), rescaled to TSS-equivalent points.
        case sessionRPE
        /// Duration times a conservative sport-typical intensity. Used only so a
        /// logged session is not silently worth zero, and always flagged as weak.
        case durationOnly

        var label: String {
            switch self {
            case .powerTSS:       "power"
            case .paceStress:     "pace"
            case .swimStress:     "swim pace"
            case .heartRateTRIMP: "heart rate"
            case .zoneTRIMP:      "heart-rate zones"
            case .sessionRPE:     "perceived effort"
            case .durationOnly:   "duration only"
            }
        }

        /// How much the resulting number should be trusted, 0 to 1. Drives whether
        /// downstream figures are shown as firm or as an estimate.
        var confidence: Double {
            switch self {
            case .powerTSS:       1.00
            case .paceStress:     0.85
            case .swimStress:     0.75
            case .heartRateTRIMP: 0.80
            case .zoneTRIMP:      0.65
            case .sessionRPE:     0.50
            case .durationOnly:   0.20
            }
        }

        private var rank: Int {
            switch self {
            case .powerTSS:       6
            case .paceStress:     5
            case .heartRateTRIMP: 4
            case .swimStress:     3
            case .zoneTRIMP:      2
            case .sessionRPE:     1
            case .durationOnly:   0
            }
        }

        static func < (a: Method, b: Method) -> Bool { a.rank < b.rank }
    }

    /// Load in TSS-equivalent points, where roughly 100 points is one hour at
    /// threshold, whatever the sport.
    var load: Double
    var method: Method
    /// Intensity factor, output relative to threshold, when the method computes one.
    var intensityFactor: Double?
    /// Raw TRIMP in its own arbitrary units, kept when heart rate drove the estimate,
    /// because it is the figure the literature reports.
    var rawTRIMP: Double?

    var confidence: Double { method.confidence }
    /// Whether any anchor behind this number was a population estimate rather than
    /// the athlete's own measurement.
    var usedEstimatedAnchor: Bool
}

// MARK: - The calculator

nonisolated enum TrainingLoad {

    // MARK: Normalized power

    /// Normalized Power, per Coggan's published four-step algorithm:
    ///   1. a 30-second rolling average of the power series
    ///   2. raise each averaged value to the fourth power
    ///   3. take the mean of those values
    ///   4. take the fourth root
    ///
    /// The fourth power is what makes NP reflect the physiological cost of variable
    /// output: surges cost disproportionately more than their arithmetic share.
    ///
    /// Returns nil for series too short for a meaningful 30-second window.
    static func normalizedPower(_ series: MetricSeries) -> Double? {
        guard !series.isEmpty, series.duration >= 60 else { return nil }
        // Work on a 1 Hz grid so the rolling window is a fixed sample count.
        let uniform = series.resampled(everySeconds: 1)
        guard uniform.count >= 30 else { return nil }

        let window = 30
        var rolling: [Double] = []
        rolling.reserveCapacity(uniform.count)
        var sum = 0.0
        for (i, value) in uniform.values.enumerated() {
            sum += value
            if i >= window { sum -= uniform.values[i - window] }
            if i >= window - 1 { rolling.append(sum / Double(window)) }
        }
        guard !rolling.isEmpty else { return nil }

        let fourthPowerMean = rolling.reduce(0.0) { $0 + pow($1, 4) } / Double(rolling.count)
        guard fourthPowerMean > 0 else { return nil }
        return pow(fourthPowerMean, 0.25)
    }

    // MARK: Grade adjustment

    /// Energy cost of running per unit distance at a given gradient, in joules per
    /// kilogram per meter.
    ///
    /// Minetti, Moia, Roi, Susta and Ferretti (2002), "Energy cost of walking and
    /// running at extreme uphill and downhill slopes", J Appl Physiol 93:1039-1046.
    /// Their fifth-order polynomial fit for RUNNING is
    ///
    ///     Cr(i) = 155.4 i^5 - 30.4 i^4 - 43.3 i^3 + 46.3 i^2 + 19.5 i + 3.6
    ///
    /// with `i` the gradient as a fraction (rise over run). At i = 0 this gives the
    /// familiar 3.6 J/kg/m. Validated over gradients from -0.45 to +0.45, so the
    /// input is clamped to that range rather than extrapolated.
    ///
    /// This is used INSTEAD OF TrainingPeaks' Normalized Graded Pace because the NGP
    /// grade-adjustment function has never been published; reproducing it would be
    /// guesswork. Minetti is peer-reviewed and measured, so the app uses it and calls
    /// the result "grade-adjusted pace" rather than claiming to be NGP.
    static func runningCostOfTransport(gradient i: Double) -> Double {
        let g = i.clamped(to: -0.45...0.45)
        let g2 = g * g
        let g3 = g2 * g
        let g4 = g3 * g
        let g5 = g4 * g
        return 155.4 * g5 - 30.4 * g4 - 43.3 * g3 + 46.3 * g2 + 19.5 * g + 3.6
    }

    /// Cost of running on the flat, the denominator for the grade adjustment.
    static let flatRunningCost = 3.6

    /// The multiplier that converts an actual speed into the equivalent flat-ground
    /// speed costing the same energy. Uphill gives a factor above 1 (you were working
    /// harder than your raw pace suggests), downhill below 1.
    static func gradeAdjustmentFactor(gradient: Double) -> Double {
        runningCostOfTransport(gradient: gradient) / flatRunningCost
    }

    /// Grade-adjusted average speed for a run, in meters per second.
    ///
    /// Walks the DISTANCE SERIES' OWN SAMPLES, computes each segment's gradient by
    /// interpolating altitude at the same two instants, converts the segment to its
    /// flat-equivalent distance via Minetti, and returns equivalent distance over elapsed
    /// time. Falls back to the plain average speed when there is no altitude data, since an
    /// indoor run has no grade to adjust for.
    ///
    /// Deliberately does NOT resample onto a fixed grid. Doing so was a real bug: a cumulative
    /// series only changes at its original sample times, so on a finer grid one step carried a
    /// whole sample interval's distance while contributing only that step's duration. The
    /// implied speed came out multiplied by the ratio of the two spacings, which turned an
    /// ordinary trail run into an intensity factor above three and a training load ten times
    /// too large. Working on the source samples makes the time and distance accounting exact
    /// by construction.
    static func gradeAdjustedSpeed(
        distanceSeries: MetricSeries?,
        altitudeSeries: MetricSeries?,
        fallbackSpeedMps: Double?
    ) -> Double? {
        guard let distanceSeries, let altitudeSeries,
              distanceSeries.count >= 4, altitudeSeries.count >= 4 else {
            return fallbackSpeedMps
        }

        var weightedEquivalentDistance = 0.0
        var totalTime = 0.0
        var totalDistance = 0.0

        for i in 1..<distanceSeries.count {
            let dd = distanceSeries.values[i] - distanceSeries.values[i - 1]
            let dt = distanceSeries.offsets[i] - distanceSeries.offsets[i - 1]
            // Skip pauses, backwards distance, and jumps faster than any human runs, which
            // are GPS glitches rather than movement.
            guard dd > 0.2, dt > 0.5, dd / dt < 12 else { continue }

            totalDistance += dd
            totalTime += dt

            // Altitude at the same two instants, interpolated so the two series need not
            // share a sampling rate.
            guard
                let z0 = altitudeSeries.value(at: distanceSeries.offsets[i - 1]),
                let z1 = altitudeSeries.value(at: distanceSeries.offsets[i])
            else {
                weightedEquivalentDistance += dd
                continue
            }
            let gradient = (z1 - z0) / dd
            // Beyond +/-45 percent Minetti's fit no longer applies, and over a short segment
            // a reading that steep is almost always barometric noise rather than terrain.
            guard abs(gradient) < 0.45 else {
                weightedEquivalentDistance += dd
                continue
            }
            weightedEquivalentDistance += dd * gradeAdjustmentFactor(gradient: gradient)
        }

        guard totalTime > 30, totalDistance > 100 else { return fallbackSpeedMps }
        let adjusted = weightedEquivalentDistance / totalTime

        // A final sanity band. Averaged over a whole session the grade adjustment cannot
        // plausibly move effective speed by more than about half in either direction, even on
        // a mountain course. Outside that, the two series disagree about time or distance, and
        // a wrong figure here propagates straight into training load, so fall back rather than
        // trust it.
        let raw = totalDistance / totalTime
        guard raw > 0 else { return fallbackSpeedMps }
        let ratio = adjusted / raw
        guard ratio > 0.6, ratio < 1.8 else { return fallbackSpeedMps ?? raw }
        return adjusted
    }

    // MARK: TRIMP

    /// Exponential (Banister) TRIMP for one session.
    ///
    /// Morton, Fitz-Clarke and Banister (1990), J Appl Physiol 69:1171-1177, weight
    /// the heart-rate reserve fraction exponentially to reflect the rising blood
    /// lactate response:
    ///
    ///     TRIMP = D x HRr x Y
    ///     HRr   = (HRavg - HRrest) / (HRmax - HRrest)
    ///     Y     = 0.64 x e^(1.92 x HRr)   for men
    ///     Y     = 0.86 x e^(1.67 x HRr)   for women
    ///
    /// `D` is duration in minutes. The sex-specific coefficients come from the
    /// respective blood-lactate profiles. When sex is unspecified the app uses the
    /// mean of the two weightings rather than silently assuming one.
    static func exponentialTRIMP(
        durationMinutes: Double,
        averageHeartRate: Double,
        restingHeartRate: Double,
        maxHeartRate: Double,
        sex: AthleteSex
    ) -> Double? {
        guard durationMinutes > 0, maxHeartRate > restingHeartRate else { return nil }
        let hrr = ((averageHeartRate - restingHeartRate) / (maxHeartRate - restingHeartRate))
            .clamped(to: 0...1)
        guard hrr > 0 else { return nil }
        return durationMinutes * hrr * lactateWeighting(hrr: hrr, sex: sex)
    }

    /// The `Y` weighting factor above.
    static func lactateWeighting(hrr: Double, sex: AthleteSex) -> Double {
        switch sex {
        case .male:   return 0.64 * exp(1.92 * hrr)
        case .female: return 0.86 * exp(1.67 * hrr)
        case .unspecified:
            // Average the two published weightings. Both curves are close over the
            // range that matters, so this is a small and clearly-stated compromise
            // rather than an assumption about the person.
            return (0.64 * exp(1.92 * hrr) + 0.86 * exp(1.67 * hrr)) / 2
        }
    }

    /// Edwards' zone-weighted TRIMP: minutes in each of five heart-rate zones
    /// multiplied by the zone number and summed.
    ///
    /// Edwards (1993), "The Heart Rate Monitor Book". Zone boundaries are 50 to 60,
    /// 60 to 70, 70 to 80, 80 to 90 and 90 to 100 percent of maximum heart rate,
    /// weighted 1 through 5.
    static func edwardsTRIMP(zoneSeconds: [Double]) -> Double? {
        guard zoneSeconds.count == 5 else { return nil }
        var total = 0.0
        for (index, seconds) in zoneSeconds.enumerated() {
            total += (seconds / 60) * Double(index + 1)
        }
        return total > 0 ? total : nil
    }

    /// The heart-rate reserve fraction the app treats as threshold when converting
    /// TRIMP onto the TSS scale. 0.85 of reserve is the conventional stand-in for
    /// lactate threshold in the absence of a lab test.
    static let thresholdReserveFraction = 0.85

    /// Convert a raw TRIMP into TSS-equivalent points.
    ///
    /// TSS is defined so one hour at threshold scores 100. To put TRIMP on the same
    /// footing we compute what TRIMP one hour at this athlete's threshold heart rate
    /// would produce, and scale by that. The result is self-consistent per athlete,
    /// which is what a fitness/fatigue model needs, and it means a hard ride scored
    /// by power and a hard run scored by heart rate contribute comparably.
    static func trimpToStressPoints(trimp: Double, sex: AthleteSex) -> Double {
        let thresholdHourTRIMP = 60 * thresholdReserveFraction
            * lactateWeighting(hrr: thresholdReserveFraction, sex: sex)
        guard thresholdHourTRIMP > 0 else { return trimp }
        return trimp / thresholdHourTRIMP * 100
    }

    // MARK: Session RPE

    /// Foster's session RPE load: RPE times session duration in minutes.
    ///
    /// Foster, Florhaug, Franklin et al. (2001), J Strength Cond Res 15:109-115.
    /// Simple, subjective, and remarkably well correlated with heart-rate based
    /// measures, which makes it the right fallback for sessions no sensor captured
    /// (most notably lifting).
    static func sessionRPELoad(rpe: Double, durationMinutes: Double) -> Double {
        max(0, rpe.clamped(to: 0...10)) * max(0, durationMinutes)
    }

    /// Convert session RPE load to TSS-equivalent points. One hour at RPE 7.5, which
    /// is about threshold effort on the Borg CR10 scale, is treated as 100 points,
    /// giving a divisor of 7.5 x 60 = 450.
    static let sessionRPEThresholdProduct = 450.0

    static func rpeToStressPoints(_ rpeLoad: Double) -> Double {
        rpeLoad / sessionRPEThresholdProduct * 100
    }

    // MARK: Zone occupancy

    /// Seconds spent in each heart-rate zone across a session, from its heart-rate
    /// series and the athlete's zone boundaries.
    static func zoneDistribution(
        heartRateSeries: MetricSeries,
        profile: ProfileSnapshot
    ) -> ZoneDistribution? {
        guard let bounds = profile.heartRateZoneBounds, heartRateSeries.count >= 2 else {
            return nil
        }
        var seconds = [Double](repeating: 0, count: ZoneDistribution.zoneCount)
        for i in 1..<heartRateSeries.count {
            let dt = heartRateSeries.offsets[i] - heartRateSeries.offsets[i - 1]
            guard dt > 0, dt < 120 else { continue }   // skip gaps
            // Use the interval's mean heart rate to attribute the time.
            let bpm = (heartRateSeries.values[i] + heartRateSeries.values[i - 1]) / 2
            var zone = bounds.count
            for (index, bound) in bounds.enumerated() where bpm < bound {
                zone = index
                break
            }
            seconds[min(zone, ZoneDistribution.zoneCount - 1)] += dt
        }
        let distribution = ZoneDistribution(seconds: seconds)
        return distribution.total > 0 ? distribution : nil
    }

    // MARK: Aerobic decoupling

    /// Aerobic decoupling: how much output per heartbeat degraded over a session.
    ///
    /// The standard method (Friel; implemented in WKO and GoldenCheetah) is to split
    /// the steady-state portion of a session in half, compute the ratio of output to
    /// heart rate in each half, and report the drop:
    ///
    ///     decoupling % = (ratio_first - ratio_second) / ratio_first x 100
    ///
    /// Output is power where available, otherwise speed. A value above about 5
    /// percent conventionally indicates the effort exceeded what current aerobic
    /// durability supports.
    ///
    /// Guards that matter: the first several minutes are dropped because heart rate
    /// lags at the start of exercise and would fake a large decoupling; the session
    /// must be long enough for two meaningful halves; and both halves must actually
    /// contain data.
    static func aerobicDecoupling(
        heartRateSeries: MetricSeries?,
        powerSeries: MetricSeries?,
        speedSeries: MetricSeries?,
        minimumDurationSeconds: Double = 1500,
        warmupDropSeconds: Double = 300
    ) -> Double? {
        guard let hr = heartRateSeries, hr.count >= 20 else { return nil }
        let output = (powerSeries?.count ?? 0) >= 20 ? powerSeries : speedSeries
        guard let output, output.count >= 20 else { return nil }

        let start = max(hr.offsets.first ?? 0, output.offsets.first ?? 0) + warmupDropSeconds
        let finish = min(hr.offsets.last ?? 0, output.offsets.last ?? 0)
        let span = finish - start
        // Needs roughly 25 minutes of steady work after the warm-up to be meaningful.
        guard span >= minimumDurationSeconds else { return nil }

        let midpoint = start + span / 2
        guard
            let hr1 = hr.mean(from: start, to: midpoint), hr1 > 40,
            let hr2 = hr.mean(from: midpoint, to: finish + 1), hr2 > 40,
            let out1 = output.mean(from: start, to: midpoint), out1 > 0,
            let out2 = output.mean(from: midpoint, to: finish + 1), out2 > 0
        else { return nil }

        let ratio1 = out1 / hr1
        let ratio2 = out2 / hr2
        guard ratio1 > 0 else { return nil }
        return (ratio1 - ratio2) / ratio1 * 100
    }

    /// The conventional threshold above which decoupling suggests the effort outran
    /// current aerobic durability.
    static let decouplingConcernThreshold = 5.0

    // MARK: - Main entry point

    /// Score one session. Walks the precedence order and returns the best-supported
    /// estimate, or nil when there is genuinely nothing to work from.
    static func score(_ workout: UnifiedWorkout, profile: ProfileSnapshot) -> TrainingLoadResult? {
        let hours = workout.movingSeconds / 3600
        let minutes = workout.movingSeconds / 60
        guard hours > 0.008 else { return nil }   // under 30 seconds is not a session

        // 1. Power against FTP. The reference method.
        if let ftpAnchor = profile.functionalThresholdPower, ftpAnchor.value > 0 {
            let np = workout.normalizedPowerWatts
                ?? workout.powerSeries.flatMap { normalizedPower($0) }
                ?? workout.averagePowerWatts
            if let np, np > 0 {
                // Coggan: TSS = (sec x NP x IF) / (FTP x 3600) x 100, which reduces
                // to IF^2 x hours x 100 since IF = NP / FTP.
                let intensity = np / ftpAnchor.value
                let load = intensity * intensity * hours * 100
                return TrainingLoadResult(
                    load: load,
                    method: .powerTSS,
                    intensityFactor: intensity,
                    rawTRIMP: nil,
                    usedEstimatedAnchor: ftpAnchor.isEstimate
                )
            }
        }

        // 2. Pace against threshold pace, grade-adjusted. Running and walking only:
        //    a cycling speed has no comparable threshold anchor without power.
        if workout.discipline == .running || workout.discipline == .walking,
           let paceAnchor = profile.thresholdPaceSecPerKm, paceAnchor.value > 0 {
            let adjusted = gradeAdjustedSpeed(
                distanceSeries: workout.distanceSeries,
                altitudeSeries: workout.altitudeSeries,
                fallbackSpeedMps: workout.effectiveSpeedMps
            )
            if let adjusted, adjusted > 0.5 {
                // Threshold pace expressed as a speed, so the ratio is the right way up.
                let thresholdSpeed = 1000 / paceAnchor.value
                let intensity = adjusted / thresholdSpeed
                // Same quadratic intensity term as TSS.
                let load = intensity * intensity * hours * 100
                return TrainingLoadResult(
                    load: load,
                    method: .paceStress,
                    intensityFactor: intensity,
                    rawTRIMP: nil,
                    usedEstimatedAnchor: paceAnchor.isEstimate
                )
            }
        }

        // 3. Heart rate. The workhorse for anyone with a watch and no power meter.
        if let avgHR = workout.averageHeartRate,
           let maxAnchor = profile.maxHeartRate,
           let restAnchor = profile.restingHeartRate,
           let trimp = exponentialTRIMP(
                durationMinutes: minutes,
                averageHeartRate: avgHR,
                restingHeartRate: restAnchor.value,
                maxHeartRate: maxAnchor.value,
                sex: profile.sex
           ) {
            let hrr = ((avgHR - restAnchor.value) / (maxAnchor.value - restAnchor.value))
                .clamped(to: 0...1)
            return TrainingLoadResult(
                load: trimpToStressPoints(trimp: trimp, sex: profile.sex),
                method: .heartRateTRIMP,
                // Express intensity relative to threshold reserve so it is comparable
                // to a power-derived intensity factor.
                intensityFactor: hrr / thresholdReserveFraction,
                rawTRIMP: trimp,
                usedEstimatedAnchor: maxAnchor.isEstimate || restAnchor.isEstimate
            )
        }

        // 4. Session RPE. Honest, subjective, and the only thing most lifting
        //    sessions offer. Prefer an explicit rating, then Apple's effort score.
        if let rpe = workout.perceivedEffort ?? workout.workoutEffortScore {
            let rpeLoad = sessionRPELoad(rpe: rpe, durationMinutes: minutes)
            return TrainingLoadResult(
                load: rpeToStressPoints(rpeLoad),
                method: .sessionRPE,
                intensityFactor: rpe / 7.5,
                rawTRIMP: nil,
                usedEstimatedAnchor: false
            )
        }

        // 5. Duration against a conservative sport-typical intensity, purely so a
        //    logged session is not worth literally nothing. Flagged as weak, and the
        //    UI says so wherever it contributes.
        let assumedIntensity = typicalIntensityFactor(for: workout.sport)
        return TrainingLoadResult(
            load: assumedIntensity * assumedIntensity * hours * 100,
            method: .durationOnly,
            intensityFactor: assumedIntensity,
            rawTRIMP: nil,
            usedEstimatedAnchor: true
        )
    }

    /// A deliberately conservative intensity assumption per sport, used only by the
    /// duration-only fallback. Set low on purpose: understating an unmeasured session
    /// is far safer than inflating the fatigue model with a session we know nothing
    /// about.
    static func typicalIntensityFactor(for sport: WorkoutSport) -> Double {
        switch sport.family {
        case .endurance:   0.70
        case .strength:    0.65
        case .mixed:       0.75
        case .restorative: 0.35
        }
    }

    // MARK: - Strength volume as load

    /// Lifting sessions rarely carry heart rate that means anything, and volume load
    /// in kilograms is not on the same scale as anything else. When a strength session
    /// has neither heart rate nor an RPE, this gives the RPE fallback something real
    /// to work with by deriving an effort estimate from the set-level RPEs the user
    /// actually logged.
    ///
    /// Returns nil when no set carried an RPE, in which case the caller falls through
    /// to the duration-only estimate rather than inventing an effort.
    static func impliedSessionRPE(for strength: StrengthSession) -> Double? {
        let rpes = strength.exercises.flatMap { $0.workingSets }.compactMap(\.rpe)
        guard rpes.count >= 2 else { return nil }
        // The session's felt cost tracks the harder sets more than the mean, so use
        // the 75th percentile rather than the average.
        return Stats.percentile(rpes, 0.75)
    }
}
