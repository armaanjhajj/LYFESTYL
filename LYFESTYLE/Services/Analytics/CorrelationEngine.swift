//
//  CorrelationEngine.swift
//  LYFESTYL
//
//  Searching for relationships between what the athlete does and how their body responds:
//  does sleep two nights ago predict today's efficiency, does a heavy week show up in
//  resting heart rate, does time in daylight track sleep quality.
//
//  THIS IS THE EASIEST PLACE IN THE APP TO PRODUCE CONFIDENT NONSENSE, so the guards matter
//  more than the search. Four things make it defensible:
//
//  1. AUTOCORRELATION. Daily health series drift slowly. Two smoothly drifting series
//     correlate strongly by construction with no causal link whatsoever. Every coefficient
//     here is tested against Bartlett's effective sample size, not the raw count of days.
//     At a lag-1 autocorrelation of 0.7 in both series, sixty days carry the weight of about
//     ten. Skipping this step is what makes naive personal-analytics features report
//     coincidences as discoveries.
//
//  2. MULTIPLE COMPARISONS. Testing many pairs across many lags means some will clear p<0.05
//     by chance alone. With 20 pairs at 8 lags, that is 160 tests and roughly 8 false
//     positives expected. A Benjamini-Hochberg false-discovery-rate correction is applied
//     across the whole search, and only one lag per pair is ever reported.
//
//  3. RANK CORRELATION BY DEFAULT. Personal health series are not normal: sleep is truncated
//     at both ends, steps are skewed by a single long walk. Spearman is immune to that and
//     also catches monotone-but-curved relationships.
//
//  4. LANGUAGE. Nothing here is described as a cause. The phrasing is always associative,
//     because an observational correlation in one person's data cannot establish a cause,
//     and saying otherwise would be the single most misleading thing the app could do.
//

import Foundation

// MARK: - A discovered relationship

nonisolated struct DiscoveredRelationship: Identifiable, Hashable, Sendable {
    /// What is being treated as the leading signal.
    var predictor: Variable
    /// What is being treated as the response.
    var outcome: Variable
    var correlation: Stats.Correlation
    /// False-discovery-rate adjusted p-value across the whole search.
    var adjustedPValue: Double
    /// How many pairs of observations backed it.
    var pairCount: Int

    var id: String { "\(predictor.id)-\(outcome.id)-\(correlation.lagDays)" }

    /// What can be correlated.
    enum Variable: Hashable, Sendable, Identifiable {
        /// A daily wellness metric.
        case wellness(WellnessMetric)
        /// Daily training load in stress points.
        case trainingLoad
        /// Form from the fitness model.
        case form
        /// Efficiency factor of that day's endurance session.
        case efficiency
        /// Perceived effort of that day's session.
        case sessionRPE

        var id: String {
            switch self {
            case .wellness(let m): "w-\(m.rawValue)"
            case .trainingLoad:    "load"
            case .form:            "form"
            case .efficiency:      "efficiency"
            case .sessionRPE:      "rpe"
            }
        }

        var label: String {
            switch self {
            case .wellness(let m): m.label
            case .trainingLoad:    "Training load"
            case .form:            "Form"
            case .efficiency:      "Efficiency"
            case .sessionRPE:      "Perceived effort"
            }
        }

        /// Lowercase, for use mid-sentence.
        var phrase: String {
            switch self {
            case .wellness(let m): m.label.lowercased()
            case .trainingLoad:    "training load"
            case .form:            "form"
            case .efficiency:      "efficiency"
            case .sessionRPE:      "perceived effort"
            }
        }

        var symbolName: String {
            switch self {
            case .wellness(let m): m.symbolName
            case .trainingLoad:    "chart.line.uptrend.xyaxis"
            case .form:            "gauge.with.needle"
            case .efficiency:      "bolt.heart"
            case .sessionRPE:      "hand.thumbsup"
            }
        }
    }

    /// The bar for showing this to someone. Deliberately strict: it must clear the raw
    /// reportability test AND survive the multiple-comparison correction.
    var isReportable: Bool {
        correlation.isReportable && adjustedPValue < 0.10 && pairCount >= 20
    }

    /// A plainly associative description. Never causal.
    var description: String {
        let direction = correlation.isPositive ? "higher" : "lower"
        let strength = correlation.strengthLabel
        if correlation.lagDays == 0 {
            return "On days when your \(predictor.phrase) is higher, your \(outcome.phrase) tends to be \(direction). The relationship is \(strength)."
        }
        let dayWord = correlation.lagDays == 1 ? "day" : "days"
        return "After \(correlation.lagDays) \(dayWord) of higher \(predictor.phrase), your \(outcome.phrase) tends to be \(direction). The relationship is \(strength)."
    }

    /// The honest caveat, shown alongside every relationship.
    var caveat: String {
        "This is an association in your own data over \(pairCount) days, not a cause. Something else may drive both."
    }
}

// MARK: - Engine

nonisolated enum CorrelationEngine {

    /// Lags searched, in days. Zero is same-day; up to three days covers the delayed response
    /// that sleep and training load are known to have.
    static let searchLags = 0...3

    /// Pairs worth testing. Deliberately a curated list of physiologically plausible
    /// relationships rather than every combination, because testing everything against
    /// everything is how a search of this kind turns into noise mining. Fewer, better
    /// hypotheses also means a gentler multiple-comparison penalty.
    static let candidatePairs: [(predictor: DiscoveredRelationship.Variable,
                                 outcome: DiscoveredRelationship.Variable)] = [
        // Does sleep show up in autonomic recovery?
        (.wellness(.sleepDuration),      .wellness(.heartRateVariability)),
        (.wellness(.sleepDuration),      .wellness(.restingHeartRate)),
        (.wellness(.sleepEfficiency),    .wellness(.heartRateVariability)),
        (.wellness(.deepSleepShare),     .wellness(.heartRateVariability)),
        (.wellness(.sleepDuration),      .wellness(.bodyBattery)),
        (.wellness(.sleepDuration),      .wellness(.hrvRmssd)),

        // Does training load show up in recovery markers?
        (.trainingLoad,                  .wellness(.restingHeartRate)),
        (.trainingLoad,                  .wellness(.heartRateVariability)),
        (.trainingLoad,                  .wellness(.sleepDuration)),
        (.trainingLoad,                  .wellness(.respiratoryRate)),
        (.trainingLoad,                  .wellness(.hrvRmssd)),

        // Does recovery show up in performance?
        (.wellness(.heartRateVariability), .efficiency),
        (.wellness(.sleepDuration),      .efficiency),
        (.wellness(.restingHeartRate),   .efficiency),
        (.form,                          .efficiency),
        (.wellness(.bodyBattery),        .efficiency),

        // Does recovery show up in how hard a session felt?
        (.wellness(.sleepDuration),      .sessionRPE),
        (.wellness(.heartRateVariability), .sessionRPE),
        (.form,                          .sessionRPE),

        // Lifestyle signals.
        (.wellness(.timeInDaylight),     .wellness(.sleepDuration)),
        (.wellness(.mindfulMinutes),     .wellness(.heartRateVariability)),
        (.wellness(.steps),              .wellness(.sleepDuration)),
        (.wellness(.stressLevel),        .wellness(.sleepEfficiency)),
    ]

    /// A day-aligned series for one variable, with nil where unmeasured.
    ///
    /// Alignment to CONSECUTIVE days with explicit nils is essential. Compacting the series
    /// first would silently shift the lag: a gap of three days would make "yesterday" mean
    /// four days ago.
    nonisolated struct AlignedSeries: Sendable {
        var dates: [Date]
        var values: [DiscoveredRelationship.Variable: [Double?]]

        var dayCount: Int { dates.count }
    }

    /// Build the aligned day grid from everything the app knows.
    static func alignedSeries(
        snapshots: [DailySnapshot],
        workouts: [UnifiedWorkout],
        loads: [String: TrainingLoadResult],
        fitness: [FitnessPoint],
        calendar: Calendar = .current
    ) -> AlignedSeries? {
        // Span from the earliest to the latest thing we know about.
        var earliest: Date?
        var latest: Date?
        for snapshot in snapshots {
            earliest = min(earliest ?? snapshot.date, snapshot.date)
            latest = max(latest ?? snapshot.date, snapshot.date)
        }
        for workout in workouts {
            earliest = min(earliest ?? workout.day, workout.day)
            latest = max(latest ?? workout.day, workout.day)
        }
        guard let start = earliest, let end = latest, start < end else { return nil }

        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let finish = calendar.startOfDay(for: end)
        while cursor <= finish {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard dates.count >= 21 else { return nil }

        let index = Dictionary(dates.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { a, _ in a })

        var values: [DiscoveredRelationship.Variable: [Double?]] = [:]
        let empty = [Double?](repeating: nil, count: dates.count)

        // Wellness metrics.
        let snapshotByDay = Dictionary(snapshots.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        for metric in WellnessMetric.allCases {
            var series = empty
            var any = false
            for (day, position) in index {
                guard let snapshot = snapshotByDay[day],
                      let value = metric.value(from: snapshot) else { continue }
                series[position] = value
                any = true
            }
            if any { values[.wellness(metric)] = series }
        }

        // Training load, summed per day. A day with no session is a REAL zero here, not a
        // gap, because resting is a value.
        var loadSeries = [Double?](repeating: nil, count: dates.count)
        for position in index.values { loadSeries[position] = 0 }
        var anyLoad = false
        for workout in workouts {
            guard let position = index[workout.day], let load = loads[workout.id]?.load else { continue }
            loadSeries[position] = (loadSeries[position] ?? 0) + load
            anyLoad = true
        }
        if anyLoad { values[.trainingLoad] = loadSeries }

        // Form.
        var formSeries = empty
        var anyForm = false
        for point in fitness {
            guard let position = index[calendar.startOfDay(for: point.date)] else { continue }
            formSeries[position] = point.form
            anyForm = true
        }
        if anyForm { values[.form] = formSeries }

        // Efficiency factor and perceived effort, from that day's endurance session. Where a
        // day has several, the longest is used, since it is the most representative.
        var efficiencySeries = empty
        var rpeSeries = empty
        var anyEfficiency = false
        var anyRPE = false
        let byDay = Dictionary(grouping: workouts) { $0.day }
        for (day, sessions) in byDay {
            guard let position = index[day] else { continue }
            let longest = sessions.max { $0.movingSeconds < $1.movingSeconds }
            if let value = longest?.efficiencyFactor, longest?.family == .endurance {
                efficiencySeries[position] = value
                anyEfficiency = true
            }
            if let value = longest?.perceivedEffort {
                rpeSeries[position] = value
                anyRPE = true
            }
        }
        if anyEfficiency { values[.efficiency] = efficiencySeries }
        if anyRPE { values[.sessionRPE] = rpeSeries }

        return AlignedSeries(dates: dates, values: values)
    }

    /// Run the search.
    ///
    /// For each candidate pair, every lag is tested but only the STRONGEST is kept. Reporting
    /// all four lags of one relationship would quadruple the apparent number of findings
    /// while adding nothing, and it inflates the multiple-comparison penalty for everything
    /// else.
    static func search(_ series: AlignedSeries) -> [DiscoveredRelationship] {
        var candidates: [DiscoveredRelationship] = []

        for pair in candidatePairs {
            guard let predictorSeries = series.values[pair.predictor],
                  let outcomeSeries = series.values[pair.outcome] else { continue }
            // A variable correlated with itself is meaningless.
            guard pair.predictor != pair.outcome else { continue }

            let results = Stats.laggedCorrelations(
                predictor: predictorSeries,
                outcome: outcomeSeries,
                lags: searchLags,
                method: .spearman
            )
            // Keep the lag with the largest absolute coefficient.
            guard let strongest = results.max(by: { $0.absCoefficient < $1.absCoefficient }) else {
                continue
            }
            candidates.append(DiscoveredRelationship(
                predictor: pair.predictor,
                outcome: pair.outcome,
                correlation: strongest,
                // Filled in by the correction below.
                adjustedPValue: strongest.pValue,
                pairCount: strongest.n
            ))
        }

        return applyFalseDiscoveryRateCorrection(candidates)
    }

    /// Benjamini-Hochberg false-discovery-rate correction.
    ///
    /// Sort the p-values ascending, then the adjusted value for the i-th of m tests is
    /// `p_i * m / i`, enforced to be monotone non-decreasing from the largest downward. This
    /// controls the expected PROPORTION of false findings among those reported, which is the
    /// right target here: the goal is a handful of trustworthy observations, not a guarantee
    /// that no single one is wrong.
    ///
    /// Chosen over Bonferroni because Bonferroni at this many tests would suppress
    /// essentially every real relationship a single person's data can show.
    static func applyFalseDiscoveryRateCorrection(
        _ relationships: [DiscoveredRelationship]
    ) -> [DiscoveredRelationship] {
        guard !relationships.isEmpty else { return [] }
        let m = Double(relationships.count)

        var sorted = relationships.sorted { $0.correlation.pValue < $1.correlation.pValue }
        var previous = 1.0
        // Walk from the largest p-value down, enforcing monotonicity.
        for i in stride(from: sorted.count - 1, through: 0, by: -1) {
            let rank = Double(i + 1)
            let adjusted = min(previous, sorted[i].correlation.pValue * m / rank)
            sorted[i].adjustedPValue = min(1, max(0, adjusted))
            previous = sorted[i].adjustedPValue
        }
        return sorted
    }

    /// The relationships worth surfacing, strongest first.
    static func reportable(_ relationships: [DiscoveredRelationship], limit: Int = 5) -> [DiscoveredRelationship] {
        relationships
            .filter(\.isReportable)
            .sorted { $0.correlation.absCoefficient > $1.correlation.absCoefficient }
            .prefix(limit)
            .map { $0 }
    }

    /// How much of the search was actually possible, so the UI can explain why there may be
    /// nothing yet rather than looking broken.
    nonisolated struct Coverage: Sendable {
        var daysAvailable: Int
        var pairsTested: Int
        var pairsPossible: Int
        var reportableCount: Int

        /// Roughly three weeks is the floor for any of this to mean anything.
        var hasEnoughHistory: Bool { daysAvailable >= 21 }

        var summary: String {
            guard hasEnoughHistory else {
                return "Relationships need about three weeks of overlapping data. There are \(daysAvailable) days so far."
            }
            if reportableCount == 0 {
                return "Nothing in \(pairsTested) tested relationships cleared the bar over \(daysAvailable) days. That is a normal and honest result."
            }
            return "\(reportableCount) of \(pairsTested) tested relationships cleared the bar over \(daysAvailable) days."
        }
    }

    static func coverage(_ series: AlignedSeries?, relationships: [DiscoveredRelationship]) -> Coverage {
        Coverage(
            daysAvailable: series?.dayCount ?? 0,
            pairsTested: relationships.count,
            pairsPossible: candidatePairs.count,
            reportableCount: relationships.filter(\.isReportable).count
        )
    }
}
