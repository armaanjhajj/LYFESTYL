//
//  RecoveryAnalysis.swift
//  LYFESTYL
//
//  Baselines, and whether today is genuinely different from them.
//
//  This is the part of the app most likely to mislead if done carelessly, so the method is
//  deliberately conservative:
//
//    ROBUST CENTRE, NOT MEAN. Baselines use the median and the scaled median absolute
//    deviation. One terrible night or one dropped sensor reading barely moves them, whereas
//    a mean and standard deviation are dragged by the very outlier you are trying to detect,
//    which systematically hides anomalies.
//
//    A THRESHOLD FROM THE PERSON'S OWN VARIABILITY. A change is only reported once it
//    exceeds the smallest worthwhile change, taken as half of this person's own robust
//    spread. This is the approach Plews and colleagues advocate for heart-rate variability
//    monitoring, and it is why the app will not tell someone their HRV is "down" when it
//    moved less than it moves on an ordinary day.
//
//    NO CROSS-METRIC HRV COMPARISON. Apple Health stores SDNN; Garmin reports RMSSD. They
//    quantify different properties of the beat-to-beat series and there is no valid
//    conversion, so each is compared only against its own history.
//
//    LOGARITHMS FOR HRV. Heart-rate variability is strongly right-skewed and its
//    day-to-day noise scales with its level, so it is analysed on the natural-log scale,
//    which is standard practice in the HRV literature. Results are reported back in
//    milliseconds.
//

import Foundation

// MARK: - Baseline

/// A robust baseline for one metric, plus where the latest reading sits against it.
nonisolated struct MetricBaseline: Identifiable, Hashable, Sendable {
    var metric: WellnessMetric
    /// Median of the trailing window.
    var center: Double
    /// Scaled median absolute deviation: a robust stand-in for the standard deviation.
    var spread: Double
    /// Observations behind the baseline.
    var sampleCount: Int
    /// The most recent reading, and when.
    var latest: Double?
    var latestDate: Date?
    /// Robust z-score of the latest reading.
    var robustZ: Double?
    /// The smallest change worth reacting to, in the metric's own units.
    var smallestWorthwhileChange: Double
    /// Trend over the window, when there is enough data.
    var trend: Stats.TrendTest?
    /// Whether the metric was analysed on the log scale (heart-rate variability is).
    var analysedOnLogScale: Bool

    var id: String { metric.rawValue }

    /// A baseline needs a real window behind it. Fourteen observations is the floor, below
    /// which "unusual for you" is not a statement anyone can make.
    static let minimumSampleCount = 14

    var isEstablished: Bool { sampleCount >= Self.minimumSampleCount && spread > 0 }

    /// Signed difference between the latest reading and the baseline centre.
    var delta: Double? {
        guard let latest else { return nil }
        return latest - center
    }

    /// Whether the latest reading is meaningfully away from baseline.
    ///
    /// This is the smallest-worthwhile-change test: has the value moved more than half this
    /// person's own day-to-day spread. It is the right question for "is this change worth
    /// noting at all", and it is deliberately sensitive.
    var isMeaningfulDeviation: Bool {
        guard isEstablished, let delta else { return false }
        return abs(delta) >= smallestWorthwhileChange
    }

    /// The threshold in robust standard deviations for calling a day genuinely unusual.
    ///
    /// The smallest worthwhile change alone is far too sensitive to headline a daily summary.
    /// At half a standard deviation, roughly six days in ten clear it for any given metric by
    /// ordinary variation, so a panel built on it would flag almost everything every day and
    /// mean nothing. Requiring 1.5 robust standard deviations brings that to roughly one day
    /// in seven per metric, which is the rate at which "this is unusual for you" is actually
    /// informative.
    static let notableZThreshold = 1.5

    /// Whether the latest reading is far enough out to lead with.
    ///
    /// Requires BOTH tests: past the smallest worthwhile change AND past the z threshold. The
    /// two catch different failure modes. A metric with a tiny spread can clear the z test on
    /// a change too small to matter, and a metric with a wide spread can clear the
    /// worthwhile-change test on a move that is entirely ordinary for it.
    var isNotableDeviation: Bool {
        guard isMeaningfulDeviation, let robustZ else { return false }
        return abs(robustZ) >= Self.notableZThreshold
    }

    /// Which way it moved, only when the move is meaningful.
    enum Deviation: String, Sendable { case above, below, normal }

    var deviation: Deviation {
        guard isMeaningfulDeviation, let delta else { return .normal }
        return delta > 0 ? .above : .below
    }

    /// Whether the move is in the metric's favourable direction. Nil for metrics with no
    /// better direction, where implying one would be wrong.
    var isFavourable: Bool? {
        guard isMeaningfulDeviation, let delta else { return nil }
        switch metric.direction {
        case .higherIsBetter: return delta > 0
        case .lowerIsBetter:  return delta < 0
        case .neutral:        return nil
        }
    }
}

// MARK: - Sleep

/// Sleep debt against a personal need, plus schedule regularity.
nonisolated struct SleepSummary: Sendable {
    /// Nights in the window, oldest first.
    var nights: [SleepNight]
    /// Median nightly sleep across the window, in hours.
    var typicalHours: Double?
    /// The user's own target, when they set one.
    var targetHours: Double?
    /// Cumulative shortfall against the target over the recent window, in hours. Only
    /// computed when a target exists, because debt against an unknown need is meaningless.
    var debtHours: Double?
    /// Sleep Regularity Index, 0 to 100.
    var regularityIndex: Double?
    /// Standard deviation of bedtime, in hours. The plainest measure of an inconsistent
    /// schedule.
    var bedtimeVariabilityHours: Double?
    /// Median sleep efficiency, when the source reported time in bed.
    var typicalEfficiency: Double?
    /// Median share of the night in each stage, for the nights that were staged.
    var stageShares: [SleepStage: Double]

    var nightCount: Int { nights.count }

    /// The Sleep Regularity Index bands reported in the sleep-regularity literature. Higher
    /// is more regular; the index is a percentage agreement measure, not a score of quality.
    var regularityBand: String? {
        guard let regularityIndex else { return nil }
        switch regularityIndex {
        case 85...:      return "very regular"
        case 70..<85:    return "fairly regular"
        case 55..<70:    return "somewhat irregular"
        default:         return "irregular"
        }
    }
}

// MARK: - Readiness

/// A composite read on how recovered the athlete is.
///
/// Deliberately NOT a score out of 100. Proprietary readiness scores hide their weighting
/// and imply a precision they do not have. Instead this reports which specific signals are
/// away from baseline and in which direction, and lets the UI say so plainly.
nonisolated struct ReadinessRead: Sendable {
    /// Signals meaningfully away from baseline right now.
    var signals: [Signal]
    /// Form from the training-load model, when there is enough history.
    var form: Double?
    var formState: FormState?

    nonisolated struct Signal: Identifiable, Hashable, Sendable {
        var metric: WellnessMetric
        var baseline: MetricBaseline
        /// Whether this particular move suggests more or less recovery.
        var suggestsRecovered: Bool?

        var id: String { metric.rawValue }
    }

    /// Signals pointing toward being under-recovered.
    var cautionSignals: [Signal] { signals.filter { $0.suggestsRecovered == false } }
    /// Signals pointing toward being well recovered.
    var positiveSignals: [Signal] { signals.filter { $0.suggestsRecovered == true } }

    /// Whether enough is known to say anything at all.
    var hasSignal: Bool { !signals.isEmpty || form != nil }

    /// A plain summary. Never a number, never a verdict on the person.
    var headline: String {
        let cautions = cautionSignals.count
        let positives = positiveSignals.count
        if cautions == 0 && positives == 0 {
            return "Everything measured is sitting in its usual range."
        }
        if cautions == 0 {
            return positives == 1
                ? "One signal is better than your usual."
                : "\(positives) signals are better than your usual."
            }
        if positives == 0 {
            return cautions == 1
                ? "One signal is outside its usual range."
                : "\(cautions) signals are outside their usual range."
        }
        return "\(cautions) signal\(cautions == 1 ? "" : "s") outside the usual range, \(positives) better than usual."
    }
}

// MARK: - Analysis

nonisolated enum RecoveryAnalysis {

    /// Metrics that are analysed on the natural-log scale, because their variability scales
    /// with their level and their distribution is strongly right-skewed.
    static let logScaleMetrics: Set<WellnessMetric> = [.heartRateVariability, .hrvRmssd]

    /// The trailing window a baseline is built from. Sixty days is long enough to be stable
    /// and short enough to track real seasonal change.
    static let baselineWindowDays = 60

    /// Build a robust baseline for one metric from a daily series.
    ///
    /// `snapshots` must be sorted oldest first. Days where the metric is missing are simply
    /// excluded rather than filled, so a gap never invents a value.
    static func baseline(
        for metric: WellnessMetric,
        snapshots: [DailySnapshot],
        windowDays: Int = RecoveryAnalysis.baselineWindowDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MetricBaseline? {
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) else {
            return nil
        }
        let points = snapshots
            .filter { $0.date >= windowStart }
            .compactMap { snapshot -> (Date, Double)? in
                guard let value = metric.value(from: snapshot), value.isFinite else { return nil }
                return (snapshot.date, value)
            }
            .sorted { $0.0 < $1.0 }
        guard points.count >= 5 else { return nil }

        let useLog = logScaleMetrics.contains(metric)
        // Log transform requires strictly positive values.
        let raw = points.map(\.1)
        let analysed = useLog ? raw.compactMap { $0 > 0 ? log($0) : nil } : raw
        guard analysed.count >= 5 else { return nil }

        guard let centerAnalysed = Stats.median(analysed),
              let spreadAnalysed = Stats.medianAbsoluteDeviation(analysed),
              let swcAnalysed = Stats.smallestWorthwhileChange(analysed)
        else { return nil }

        let latestRaw = points.last?.1
        let latestAnalysed = useLog ? latestRaw.flatMap { $0 > 0 ? log($0) : nil } : latestRaw
        let robustZ = latestAnalysed.flatMap { Stats.robustZScore($0, in: analysed) }

        // Report in the metric's own units. On the log scale the centre exponentiates back
        // to the geometric median, and the threshold is converted at that centre so it reads
        // as milliseconds rather than log units.
        let center = useLog ? exp(centerAnalysed) : centerAnalysed
        let spread = useLog ? center * spreadAnalysed : spreadAnalysed
        let swc = useLog ? center * swcAnalysed : swcAnalysed

        return MetricBaseline(
            metric: metric,
            center: center,
            spread: spread,
            sampleCount: analysed.count,
            latest: latestRaw,
            latestDate: points.last?.0,
            robustZ: robustZ,
            smallestWorthwhileChange: swc,
            trend: analysed.count >= 10 ? Stats.mannKendall(analysed) : nil,
            analysedOnLogScale: useLog
        )
    }

    /// Baselines for every metric with enough data.
    static func baselines(
        snapshots: [DailySnapshot],
        metrics: [WellnessMetric] = WellnessMetric.allCases,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WellnessMetric: MetricBaseline] {
        var result: [WellnessMetric: MetricBaseline] = [:]
        for metric in metrics {
            if let baseline = baseline(for: metric, snapshots: snapshots, now: now, calendar: calendar) {
                result[metric] = baseline
            }
        }
        return result
    }

    // MARK: - Sleep

    /// Summarise sleep across a window.
    static func sleepSummary(
        snapshots: [DailySnapshot],
        windowDays: Int = 30,
        targetHours: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepSummary {
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let nights = snapshots
            .filter { $0.date >= windowStart }
            .compactMap(\.sleep)
            .sorted { $0.date < $1.date }

        let hours = nights.map(\.asleepHours)
        let typical = Stats.median(hours)

        // Debt only against an explicit target. Assuming eight hours for everyone would
        // manufacture a deficit for a genuine short sleeper.
        var debt: Double?
        if let targetHours, targetHours > 0, !nights.isEmpty {
            // Only the last two weeks: older shortfall is not a live debt.
            let recent = nights.suffix(14)
            debt = recent.reduce(0.0) { $0 + max(0, targetHours - $1.asleepHours) }
        }

        let bedtimes = nights.map { $0.bedtimeHour(calendar: calendar) }

        // Median stage shares over the nights that were actually staged.
        var stageShares: [SleepStage: Double] = [:]
        for stage in [SleepStage.deep, .rem, .core] {
            let shares = nights.compactMap { $0.stageFraction(stage) }
            if shares.count >= 3, let median = Stats.median(shares) {
                stageShares[stage] = median
            }
        }

        return SleepSummary(
            nights: nights,
            typicalHours: typical,
            targetHours: targetHours,
            debtHours: debt,
            regularityIndex: sleepRegularityIndex(nights: nights, calendar: calendar),
            bedtimeVariabilityHours: bedtimes.count >= 5 ? Stats.standardDeviation(bedtimes) : nil,
            typicalEfficiency: Stats.median(nights.compactMap(\.efficiency)),
            stageShares: stageShares
        )
    }

    /// Sleep Regularity Index.
    ///
    /// The index is the percentage of minutes in which a person's sleep or wake state matches
    /// the state at the same clock minute exactly 24 hours earlier, rescaled to run from
    /// -100 (perfectly irregular) through 0 (chance) to 100 (identical every day):
    ///
    ///     SRI = -100 + (200 / (M(N-1))) x sum over days and minutes of delta(state, state+24h)
    ///
    /// Computed here at ONE-MINUTE resolution over the sleep intervals reconstructed from the
    /// nights. Needs at least seven consecutive nights, since the measure is about
    /// day-to-day agreement.
    static func sleepRegularityIndex(
        nights: [SleepNight],
        calendar: Calendar = .current
    ) -> Double? {
        guard nights.count >= 7 else { return nil }

        // Build a minute-resolution asleep/awake timeline over the covered span.
        guard let first = nights.first, let last = nights.last else { return nil }
        let start = calendar.startOfDay(for: first.bedtime)
        let end = calendar.startOfDay(for: last.wakeTime).addingTimeInterval(24 * 3600)
        let totalMinutes = Int(end.timeIntervalSince(start) / 60)
        guard totalMinutes > 2 * 24 * 60 else { return nil }

        var asleep = [Bool](repeating: false, count: totalMinutes)
        for night in nights {
            let from = max(0, Int(night.bedtime.timeIntervalSince(start) / 60))
            let to = min(totalMinutes, Int(night.wakeTime.timeIntervalSince(start) / 60))
            guard from < to else { continue }
            for minute in from..<to { asleep[minute] = true }
        }

        let dayMinutes = 24 * 60
        var matches = 0
        var comparisons = 0
        for minute in 0..<(totalMinutes - dayMinutes) {
            comparisons += 1
            if asleep[minute] == asleep[minute + dayMinutes] { matches += 1 }
        }
        guard comparisons > 0 else { return nil }
        return -100 + 200 * Double(matches) / Double(comparisons)
    }

    // MARK: - Readiness

    /// Which signals are away from baseline right now.
    ///
    /// Only metrics that genuinely reflect recovery are considered. Step count is not a
    /// recovery signal, and including it would dilute the read with noise.
    static let recoverySignalMetrics: [WellnessMetric] = [
        .heartRateVariability, .hrvRmssd, .restingHeartRate, .respiratoryRate,
        .sleepDuration, .sleepEfficiency, .wristTemperature, .bodyBattery, .stressLevel,
    ]

    static func readiness(
        snapshots: [DailySnapshot],
        baselines: [WellnessMetric: MetricBaseline],
        form: Double?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReadinessRead {
        // Only judge against readings from the last two days: a four-day-old HRV value says
        // nothing about this morning.
        let cutoff = calendar.date(byAdding: .day, value: -2, to: now) ?? now

        var signals: [ReadinessRead.Signal] = []
        for metric in recoverySignalMetrics {
            guard let baseline = baselines[metric],
                  baseline.isEstablished,
                  // The stricter test: leading a daily summary with every half-sigma wobble
                  // would flag most metrics most days and tell the user nothing.
                  baseline.isNotableDeviation,
                  let latestDate = baseline.latestDate, latestDate >= cutoff
            else { continue }
            signals.append(ReadinessRead.Signal(
                metric: metric,
                baseline: baseline,
                // Wrist temperature has no favourable direction in general, but a deviation
                // in EITHER direction is worth noticing, so it is reported as a caution.
                suggestsRecovered: metric == .wristTemperature ? false : baseline.isFavourable
            ))
        }

        return ReadinessRead(
            signals: signals,
            form: form,
            formState: form.map { FormState.classify(form: $0) }
        )
    }

    // MARK: - Resting heart rate drift

    /// A sustained shift in the resting-heart-rate baseline, which is the single most
    /// reliable early marker of accumulating fatigue or an oncoming illness.
    ///
    /// Uses CUSUM rather than a two-window comparison, because it accumulates weak evidence:
    /// a persistent two-beat elevation is exactly what matters and a week-versus-week check
    /// would miss it.
    static func restingHeartRateShift(
        snapshots: [DailySnapshot],
        windowDays: Int = 60,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Stats.ChangePoint? {
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) else {
            return nil
        }
        let values = snapshots
            .filter { $0.date >= windowStart }
            .sorted { $0.date < $1.date }
            .compactMap(\.restingHeartRate)
        guard values.count >= 25 else { return nil }
        return Stats.cusumChangePoint(values)
    }
}
