//
//  InsightBuilder.swift
//  LYFESTYL
//
//  Where the analysis becomes something worth reading.
//
//  Each builder below takes one analysis result and, only if it clears that analysis's own
//  bar, produces a `HealthInsight` with the numbers attached. Nothing here invents a
//  finding: every branch either has the evidence or returns nothing.
//
//  Rules that apply to every insight produced here:
//
//    - No score, no grade, no rating of the person.
//    - No causal claim. Associations are described as associations.
//    - No injury or illness prediction. The app can say resting heart rate is elevated and
//      what that is associated with in the literature; it cannot say someone is getting sick.
//    - Confidence reflects the actual evidence, including whether the athlete profile behind
//      a number was measured or estimated.
//    - Every number shown traces to measured data.
//

import Foundation

// MARK: - Input

/// Everything the builders need, computed once.
nonisolated struct AnalysisContext: Sendable {
    var workouts: [UnifiedWorkout]
    var snapshots: [DailySnapshot]
    var profile: ProfileSnapshot
    var loads: [String: TrainingLoadResult]
    var zones: [String: ZoneDistribution]
    var fitness: [FitnessPoint]
    var loadRamp: LoadRamp
    var weeks: [TrainingWeek]
    var consistency: FitnessModel.Consistency?
    var baselines: [WellnessMetric: MetricBaseline]
    var sleep: SleepSummary
    var readiness: ReadinessRead
    var exerciseProgress: [ExerciseProgress]
    var muscleVolume: [MuscleVolume]
    var balanceRatios: [BalanceRatio]
    var plateaus: [StrengthAnalysis.PlateauCheck]
    var strengthRecords: [StrengthAnalysis.StrengthRecord]
    var distanceBests: [DistanceBest]
    var racePredictions: [RacePrediction.Prediction]
    var relationships: [DiscoveredRelationship]
    var correlationCoverage: CorrelationEngine.Coverage
    var intensity: FitnessModel.IntensityDistribution?
    var restingHeartRateShift: Stats.ChangePoint?
    var now: Date

    /// Sources that contributed anything.
    var sources: [DataSource] {
        var set = Set<DataSource>()
        for workout in workouts { set.insert(workout.origin.source) }
        for snapshot in snapshots { set.formUnion(snapshot.contributingSources) }
        return set.sorted { $0.fieldPriority > $1.fieldPriority }
    }

    /// Days of history, which gates several insights.
    var daysOfHistory: Int {
        guard let earliest = workouts.map(\.day).min() ?? snapshots.map(\.date).min() else { return 0 }
        return Calendar.current.dateComponents([.day], from: earliest, to: now).day ?? 0
    }

    /// Whether any load figure rests on an estimated anchor, which caps confidence for
    /// everything derived from load.
    var loadUsesEstimatedAnchor: Bool {
        loads.values.contains { $0.usedEstimatedAnchor }
    }

    /// The weakest method used across recent load scoring, which is what the honest
    /// confidence for load-derived insights should follow.
    var weakestRecentLoadMethod: TrainingLoadResult.Method? {
        let recent = workouts
            .filter { now.timeIntervalSince($0.start) < 28 * 86400 }
            .compactMap { loads[$0.id]?.method }
        return recent.min()
    }
}

// MARK: - Builder

nonisolated enum InsightBuilder {

    /// Build every insight the data supports.
    static func build(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        insights.append(contentsOf: recoveryInsights(context))
        insights.append(contentsOf: trainingLoadInsights(context))
        insights.append(contentsOf: sleepInsights(context))
        insights.append(contentsOf: enduranceInsights(context))
        insights.append(contentsOf: strengthInsights(context))
        insights.append(contentsOf: relationshipInsights(context))
        insights.append(contentsOf: consistencyInsights(context))
        insights.append(contentsOf: milestoneInsights(context))
        insights.append(contentsOf: dataQualityInsights(context))
        return insights.ranked
    }

    // MARK: - Recovery

    static func recoveryInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []

        // Each recovery signal currently away from its baseline.
        for signal in context.readiness.signals {
            let baseline = signal.baseline
            guard let latest = baseline.latest, let delta = baseline.delta else { continue }
            let metric = signal.metric
            let direction = delta > 0 ? "higher" : "lower"
            let favourable = signal.suggestsRecovered == true

            var detail: String
            switch metric {
            case .restingHeartRate:
                detail = delta > 0
                    ? "Resting heart rate is above your usual range. An elevated resting heart rate is commonly associated with accumulated training load, poor sleep, alcohol, heat, or the early stage of an illness."
                    : "Resting heart rate is below your usual range, which usually follows a period of lighter load or good sleep."
            case .heartRateVariability, .hrvRmssd:
                detail = delta > 0
                    ? "Heart-rate variability is above your usual range. Higher variability generally accompanies a well-recovered state."
                    : "Heart-rate variability is below your usual range. Suppressed variability is commonly associated with fatigue, disrupted sleep, or stress from outside training."
            case .respiratoryRate:
                detail = delta > 0
                    ? "Overnight breathing rate is above your usual range. This is one of the earlier signals to move when the body is under strain."
                    : "Overnight breathing rate is below your usual range."
            case .wristTemperature:
                detail = "Overnight wrist temperature is \(direction) than your usual range. Apple records this as a deviation from your own baseline rather than an absolute temperature."
            case .bodyBattery:
                detail = delta > 0
                    ? "Body Battery is above your usual range, which reflects a well-recovered state on Garmin's own measure."
                    : "Body Battery is below your usual range, which Garmin bases on stress, activity and sleep across the day."
            case .stressLevel:
                detail = delta > 0
                    ? "All-day stress is above your usual range on Garmin's measure."
                    : "All-day stress is below your usual range."
            case .sleepDuration:
                detail = delta > 0
                    ? "You slept longer than your usual range."
                    : "You slept less than your usual range. A single short night matters far less than a run of them, so this is worth watching rather than reacting to."
            case .sleepEfficiency:
                detail = delta > 0
                    ? "You spent more of your time in bed actually asleep than usual."
                    : "More of your time in bed was spent awake than usual. Efficiency is asleep time as a share of time in bed, so it moves with restlessness rather than with how long you were down for."
            default:
                detail = "\(metric.label) is \(direction) than your usual range."
            }

            // Confidence follows the sample behind the baseline, not how interesting it is.
            let confidence: InsightConfidence = baseline.sampleCount >= 30
                ? .high : (baseline.sampleCount >= MetricBaseline.minimumSampleCount ? .moderate : .exploratory)

            insights.append(HealthInsight(
                id: "recovery-\(metric.rawValue)",
                kind: .recovery,
                tone: favourable ? .positive : .attention,
                confidence: confidence,
                headline: "\(metric.label.uppercased()) IS \(direction.uppercased()) THAN USUAL",
                detail: detail,
                evidence: [
                    InsightEvidence("Latest", metric.format(latest, includeUnit: true)),
                    InsightEvidence(
                        "Your usual",
                        metric.format(baseline.center, includeUnit: true),
                        context: "median of \(baseline.sampleCount) days"
                    ),
                    InsightEvidence(
                        "Change",
                        Formatting.signed(delta, places: metric.fractionDigits, unit: metric.unit),
                        context: "your day-to-day spread is \(metric.format(baseline.spread, includeUnit: true))"
                    ),
                ],
                sources: context.sources,
                series: series(for: metric, snapshots: context.snapshots, baseline: baseline.center),
                // Attention-worthy signals rank above favourable ones.
                priority: favourable ? 40 : 90,
                metric: metric
            ))
        }

        // A sustained shift in resting heart rate, which a single day cannot show.
        if let shift = context.restingHeartRateShift, abs(shift.magnitudeInSD) >= 1 {
            let rising = shift.isUpward
            insights.append(HealthInsight(
                id: "recovery-rhr-shift",
                kind: .recovery,
                tone: rising ? .attention : .positive,
                confidence: .high,
                headline: rising ? "RESTING HEART RATE HAS SHIFTED UP" : "RESTING HEART RATE HAS SETTLED LOWER",
                detail: rising
                    ? "This is a sustained change in the baseline itself, not a single unusual day. A persistent rise in resting heart rate is one of the more reliable early markers that load is accumulating faster than recovery."
                    : "This is a sustained change in the baseline itself. A settled, lower resting heart rate generally follows a period where recovery has kept up with load.",
                evidence: [
                    InsightEvidence("Before", "\(Int(shift.meanBefore.rounded())) bpm"),
                    InsightEvidence("Since", "\(Int(shift.meanAfter.rounded())) bpm"),
                    InsightEvidence(
                        "Shift",
                        Formatting.signed(shift.meanAfter - shift.meanBefore, places: 1, unit: "bpm"),
                        context: "\(Formatting.decimal(abs(shift.magnitudeInSD), places: 1))x your normal variation"
                    ),
                ],
                sources: context.sources,
                series: series(for: .restingHeartRate, snapshots: context.snapshots,
                               baseline: shift.meanBefore),
                priority: 95,
                metric: .restingHeartRate
            ))
        }

        return insights
    }

    // MARK: - Training load

    static func trainingLoadInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        let ramp = context.loadRamp

        // Load-derived confidence is capped by the weakest scoring method in use: a month
        // scored from duration alone cannot support a confident statement about load.
        let methodConfidence: InsightConfidence = {
            switch context.weakestRecentLoadMethod {
            case .powerTSS, .paceStress:      return .high
            case .heartRateTRIMP, .swimStress: return context.loadUsesEstimatedAnchor ? .moderate : .high
            case .zoneTRIMP, .sessionRPE:     return .moderate
            case .durationOnly, .none:        return .exploratory
            }
        }()

        // Form, and what it means.
        if let latest = context.fitness.last, ramp.isEstablished {
            let state = FormState.classify(form: latest.form)
            let tone: InsightTone = (state == .overreached || state == .strained) ? .attention
                : (state == .fresh || state == .ready) ? .positive : .neutral
            insights.append(HealthInsight(
                id: "load-form",
                kind: .trainingLoad,
                tone: tone,
                confidence: methodConfidence,
                headline: state.label,
                detail: state.describing + " Form is your accumulated fitness minus your recent fatigue, so it is a measure of freshness rather than of ability.",
                evidence: [
                    InsightEvidence("Fitness", Formatting.decimal(latest.fitness, places: 0),
                                    context: "42-day average load"),
                    InsightEvidence("Fatigue", Formatting.decimal(latest.fatigue, places: 0),
                                    context: "7-day average load"),
                    InsightEvidence("Form", Formatting.signed(latest.form, places: 0)),
                ],
                sources: context.sources,
                series: InsightSeries(
                    points: context.fitness.suffix(90).map {
                        InsightSeries.Point(date: $0.date, value: $0.fitness)
                    },
                    baseline: nil,
                    unit: nil
                ),
                priority: 80
            ))
        }

        // A sharp increase in load.
        if let band = ramp.band, band == .spike, let ratio = ramp.ratio {
            var evidence: [InsightEvidence] = [
                InsightEvidence("Recent load", Formatting.decimal(ramp.acute, places: 0),
                                context: "7-day weighted average"),
                InsightEvidence("Baseline load", Formatting.decimal(ramp.chronic, places: 0),
                                context: "28-day weighted average"),
                InsightEvidence("Ratio", Formatting.decimal(ratio, places: 2)),
            ]
            if let uncoupled = ramp.uncoupledRatio {
                evidence.append(InsightEvidence(
                    "Uncoupled ratio", Formatting.decimal(uncoupled, places: 2),
                    context: "last 7 days against the 21 before them"
                ))
            }
            insights.append(HealthInsight(
                id: "load-spike",
                kind: .trainingLoad,
                tone: .attention,
                confidence: methodConfidence,
                headline: "RECENT LOAD IS WELL ABOVE YOUR BASELINE",
                detail: "The last week carries considerably more load than the previous month. Worth knowing, though the popular idea that a specific ratio predicts injury has been seriously questioned in the research, so treat this as a description of a sharp change rather than a warning.",
                evidence: evidence,
                sources: context.sources,
                series: InsightSeries(
                    points: context.fitness.suffix(60).map {
                        InsightSeries.Point(date: $0.date, value: $0.load)
                    },
                    baseline: ramp.chronic,
                    unit: nil
                ),
                priority: 85
            ))
        }

        // Monotony: high load with no variation.
        if let week = context.weeks.last,
           let monotony = week.monotony,
           monotony >= FitnessModel.monotonyConcernThreshold,
           week.totalLoad > 50 {
            insights.append(HealthInsight(
                id: "load-monotony",
                kind: .trainingLoad,
                tone: .attention,
                confidence: methodConfidence,
                headline: "EVERY DAY LOOKED THE SAME LAST WEEK",
                detail: "Training monotony is the ratio of your average daily load to how much it varied. Foster's work associated high monotony with worse outcomes than the same total load spread unevenly. Harder hard days and genuinely easy easy days lower it.",
                evidence: [
                    InsightEvidence("Monotony", Formatting.decimal(monotony, places: 2),
                                    context: "above 2 is the usual concern point"),
                    InsightEvidence("Week load", Formatting.decimal(week.totalLoad, places: 0)),
                    InsightEvidence("Rest days", "\(week.restDays)"),
                ],
                sources: context.sources,
                priority: 70
            ))
        }

        // Intensity distribution against the polarized pattern.
        if let intensity = context.intensity, intensity.hasEnoughData {
            let gap = intensity.easyGapFromPublishedTarget
            if abs(gap) >= 12 {
                let tooHard = gap < 0
                insights.append(HealthInsight(
                    id: "load-intensity-distribution",
                    kind: .trainingLoad,
                    tone: tooHard ? .attention : .neutral,
                    confidence: .high,
                    headline: tooHard ? "LESS EASY WORK THAN THE USUAL PATTERN" : "MOST OF YOUR WORK IS EASY",
                    detail: tooHard
                        ? "Studies of well-trained endurance athletes consistently find around 80 percent of their time at low intensity. Yours is lower, which tends to mean the easy days are not quite easy enough to let the hard ones be hard."
                        : "Studies of well-trained endurance athletes consistently find around 80 percent of their time at low intensity, and yours is at or above that. This is the distribution most of the literature describes.",
                    evidence: [
                        InsightEvidence("Easy (zones 1 to 2)", Formatting.percent(fraction: intensity.easyFraction)),
                        InsightEvidence("Moderate (zone 3)", Formatting.percent(fraction: intensity.moderateFraction)),
                        InsightEvidence("Hard (zones 4 to 5)", Formatting.percent(fraction: intensity.hardFraction)),
                    ],
                    sources: context.sources,
                    priority: 55
                ))
            }
        }

        return insights
    }

    // MARK: - Sleep

    static func sleepInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        let sleep = context.sleep
        guard sleep.nightCount >= 7 else { return [] }

        // Schedule regularity, which the literature links to outcomes independently of
        // duration.
        if let index = sleep.regularityIndex, let band = sleep.regularityBand, index < 70 {
            var evidence: [InsightEvidence] = [
                InsightEvidence("Regularity index", Formatting.decimal(index, places: 0),
                                context: "0 is chance, 100 is identical every day"),
            ]
            if let variability = sleep.bedtimeVariabilityHours {
                evidence.append(InsightEvidence(
                    "Bedtime swing",
                    "\(Formatting.decimal(variability, places: 1)) h",
                    context: "standard deviation across \(sleep.nightCount) nights"
                ))
            }
            if let typical = sleep.typicalHours {
                evidence.append(InsightEvidence("Typical night", Formatting.decimal(typical, places: 1) + " h"))
            }
            insights.append(HealthInsight(
                id: "sleep-regularity",
                kind: .sleep,
                tone: .attention,
                confidence: sleep.nightCount >= 21 ? .high : .moderate,
                headline: "YOUR SLEEP SCHEDULE IS \(band.uppercased())",
                detail: "The Sleep Regularity Index measures how closely your sleep and wake times repeat from one day to the next. Research consistently finds regularity matters for health outcomes separately from how long you sleep, so a consistent schedule is worth as much attention as total hours.",
                evidence: evidence,
                sources: context.sources,
                priority: 65,
                metric: .bedtimeConsistency
            ))
        }

        // Stage composition against population reference bands.
        for stage in [SleepStage.deep, .rem] {
            guard let share = sleep.stageShares[stage],
                  let reference = stage.typicalFractionRange,
                  !reference.contains(share)
            else { continue }
            let low = share < reference.lowerBound
            insights.append(HealthInsight(
                id: "sleep-stage-\(stage.rawValue)",
                kind: .sleep,
                tone: .neutral,
                confidence: .moderate,
                headline: "\(stage.label.uppercased()) SLEEP IS \(low ? "BELOW" : "ABOVE") THE TYPICAL BAND",
                detail: "Adults typically spend \(Formatting.percent(fraction: reference.lowerBound)) to \(Formatting.percent(fraction: reference.upperBound)) of the night in \(stage.label.lowercased()) sleep. These are population reference ranges rather than targets, and stage detection from a wrist device is an estimate, so this is context rather than a finding.",
                evidence: [
                    InsightEvidence("Your median", Formatting.percent(fraction: share),
                                    context: "across \(sleep.nightCount) nights"),
                    InsightEvidence(
                        "Typical range",
                        "\(Formatting.percent(fraction: reference.lowerBound)) to \(Formatting.percent(fraction: reference.upperBound))"
                    ),
                ],
                sources: context.sources,
                priority: 30,
                metric: stage == .deep ? .deepSleepShare : .remSleepShare
            ))
        }

        // Sleep debt, only against a target the user actually set.
        if let debt = sleep.debtHours, let target = sleep.targetHours, debt >= target {
            insights.append(HealthInsight(
                id: "sleep-debt",
                kind: .sleep,
                tone: .attention,
                confidence: .high,
                headline: "SLEEP HAS BEEN SHORT OF YOUR TARGET",
                detail: "Across the last two weeks you have fallen short of the target you set by roughly a full night's worth in total.",
                evidence: [
                    InsightEvidence("Shortfall", "\(Formatting.decimal(debt, places: 1)) h",
                                    context: "cumulative over 14 nights"),
                    InsightEvidence("Your target", "\(Formatting.decimal(target, places: 1)) h"),
                    InsightEvidence("Typical night",
                                    "\(Formatting.decimal(sleep.typicalHours ?? 0, places: 1)) h"),
                ],
                sources: context.sources,
                series: series(for: .sleepDuration, snapshots: context.snapshots, baseline: target),
                priority: 75,
                metric: .sleepDuration
            ))
        }

        return insights
    }

    // MARK: - Endurance

    static func enduranceInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []

        for discipline in [WorkoutSport.Discipline.running, .cycling] {
            // Efficiency factor: output per heartbeat, the effort-independent fitness signal.
            if let (test, changePercent) = PerformanceAnalysis.efficiencyTrend(
                workouts: context.workouts, discipline: discipline
            ), test.isSignificant, abs(changePercent) >= 3 {
                let improving = test.direction == .increasing
                let name = discipline == .running ? "running" : "cycling"
                insights.append(HealthInsight(
                    id: "endurance-efficiency-\(discipline.rawValue)",
                    kind: .endurance,
                    tone: improving ? .positive : .attention,
                    confidence: test.n >= 15 ? .high : .moderate,
                    headline: improving
                        ? "YOUR \(name.uppercased()) EFFICIENCY IS IMPROVING"
                        : "YOUR \(name.uppercased()) EFFICIENCY IS DRIFTING DOWN",
                    detail: improving
                        ? "Efficiency factor is how much output you get per heartbeat. Because it is measured relative to your own heart rate, it rises when aerobic fitness improves rather than when you simply try harder. That is what makes it a cleaner progress signal than pace."
                        : "Efficiency factor is how much output you get per heartbeat. A fall can mean accumulated fatigue, but heat, altitude, illness and a change in terrain all move it too, so it is worth reading alongside your recovery signals rather than alone.",
                    evidence: [
                        InsightEvidence("Change", Formatting.signed(changePercent, places: 1, unit: "%"),
                                        context: "over \(test.n) steady sessions"),
                        InsightEvidence("Trend strength", Formatting.decimal(abs(test.tau), places: 2),
                                        context: "Kendall tau, 0 to 1"),
                        InsightEvidence("Significance", "p = \(Formatting.decimal(test.pValue, places: 3))"),
                    ],
                    sources: context.sources,
                    series: InsightSeries(
                        points: PerformanceAnalysis.efficiencySeries(
                            workouts: context.workouts, discipline: discipline
                        ).map { InsightSeries.Point(date: $0.date, value: $0.value) },
                        baseline: nil,
                        unit: nil
                    ),
                    priority: improving ? 60 : 72
                ))
            }
        }

        // Aerobic durability, from within-session decoupling.
        let decoupling = PerformanceAnalysis.decouplingSeries(workouts: context.workouts)
        if decoupling.count >= 5 {
            let recent = Array(decoupling.suffix(5)).map(\.value)
            if let median = Stats.median(recent), median > TrainingLoad.decouplingConcernThreshold {
                insights.append(HealthInsight(
                    id: "endurance-decoupling",
                    kind: .endurance,
                    tone: .attention,
                    confidence: decoupling.count >= 10 ? .high : .moderate,
                    headline: "OUTPUT PER HEARTBEAT IS FADING WITHIN SESSIONS",
                    detail: "Aerobic decoupling compares the first half of a steady session to the second. When output per heartbeat drops by more than about 5 percent, it conventionally means the effort ran ahead of current aerobic durability. More steady low-intensity volume is the usual way that number comes down.",
                    evidence: [
                        InsightEvidence("Recent median", Formatting.percentValue(median),
                                        context: "last \(recent.count) qualifying sessions"),
                        InsightEvidence("Usual concern point", "5%"),
                        InsightEvidence("Sessions measured", "\(decoupling.count)"),
                    ],
                    sources: context.sources,
                    series: InsightSeries(
                        points: decoupling.map { InsightSeries.Point(date: $0.date, value: $0.value) },
                        baseline: TrainingLoad.decouplingConcernThreshold,
                        unit: "%"
                    ),
                    priority: 68
                ))
            }
        }

        // Race predictions from a genuine recent best.
        let reliable = context.racePredictions.filter(\.isReliable)
        if let base = reliable.first, !reliable.isEmpty {
            insights.append(HealthInsight(
                id: "endurance-predictions",
                kind: .endurance,
                tone: .neutral,
                confidence: .moderate,
                headline: "WHAT YOUR RECENT FORM PROJECTS TO",
                detail: "These come from Riegel's endurance formula, which scales a known time by distance raised to the power 1.06. It is a decent rule of thumb within about a fourfold change in distance and it assumes you are trained for the distance, so treat them as projections rather than predictions.",
                evidence: reliable.prefix(4).map { prediction in
                    InsightEvidence(
                        prediction.distanceName,
                        Formatting.duration(prediction.predictedSeconds),
                        context: Formatting.pace(secondsPerKm: prediction.pacePerKm, metric: true)
                    )
                } + [
                    InsightEvidence(
                        "Based on",
                        Formatting.duration(base.basedOnSeconds),
                        context: "your \(Formatting.distance(base.basedOnDistanceMeters, metric: true)) on \(Formatting.relativeDay(base.basedOnDate, now: context.now))"
                    ),
                ],
                sources: context.sources,
                priority: 35
            ))
        }

        return insights
    }

    // MARK: - Strength

    static func strengthInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []

        // Regions getting materially less than the published range.
        let neglected = context.muscleVolume.filter {
            $0.system != .cardio && $0.standing == .belowRange && $0.setsPerWeek > 0
        }
        let untrained = context.muscleVolume.filter { $0.system != .cardio && $0.standing == .untrained }
        if !neglected.isEmpty || !untrained.isEmpty {
            let names = (untrained + neglected).prefix(3).map { $0.system.label.capitalized }
            insights.append(HealthInsight(
                id: "strength-volume-gaps",
                kind: .strength,
                tone: .neutral,
                confidence: .high,
                headline: "\(names.joined(separator: ", ").uppercased()) ARE GETTING LESS WORK",
                detail: "Reviews of the hypertrophy literature report a dose-response across roughly 10 to 20 hard sets per muscle per week, with returns flattening after that. This is population context, not a target you are missing, and it says nothing about whether your programme suits your goals.",
                evidence: (untrained + neglected).prefix(4).map { volume in
                    InsightEvidence(
                        volume.system.label.capitalized,
                        volume.setsPerWeek > 0 ? "\(Formatting.decimal(volume.setsPerWeek, places: 1)) sets/week" : "no work logged",
                        context: volume.daysSinceLastTrained.map { $0 == 0 ? "trained today" : "\($0) days ago" }
                    )
                } + [InsightEvidence("Usual range", "10 to 20 sets/week")],
                sources: context.sources,
                priority: 62
            ))
        }

        // A movement that has genuinely stalled.
        let stalled = context.plateaus.filter(\.isPlateau)
        if let plateau = stalled.max(by: { $0.sessionsConsidered < $1.sessionsConsidered }) {
            insights.append(HealthInsight(
                id: "strength-plateau-\(plateau.trackingKey)",
                kind: .strength,
                tone: .attention,
                confidence: plateau.sessionsConsidered >= 12 ? .high : .moderate,
                headline: "\(plateau.exerciseName.uppercased()) HAS NOT MOVED",
                detail: "Across your last \(plateau.sessionsConsidered) sessions of this movement there is no statistically detectable trend in estimated one-rep max, up or down. That is a plateau in the strict sense: not that you are getting weaker, but that the data shows no direction.",
                evidence: [
                    InsightEvidence("Sessions", "\(plateau.sessionsConsidered)"),
                    InsightEvidence("Estimated max then",
                                    Formatting.weight(kilograms: plateau.startValue, unit: .kg)),
                    InsightEvidence("Estimated max now",
                                    Formatting.weight(kilograms: plateau.endValue, unit: .kg),
                                    context: Formatting.signed(plateau.changeKg, places: 1, unit: "kg")),
                    InsightEvidence("Significance", "p = \(Formatting.decimal(plateau.test.pValue, places: 3))",
                                    context: "no trend detected"),
                ],
                sources: context.sources,
                series: seriesFor(trackingKey: plateau.trackingKey, progress: context.exerciseProgress),
                priority: 66
            ))
        }

        // A movement clearly progressing.
        let progressing = context.plateaus.filter { $0.isProgressing && ($0.changePercent ?? 0) >= 3 }
        if let best = progressing.max(by: { ($0.changePercent ?? 0) < ($1.changePercent ?? 0) }) {
            insights.append(HealthInsight(
                id: "strength-progress-\(best.trackingKey)",
                kind: .strength,
                tone: .positive,
                confidence: best.sessionsConsidered >= 12 ? .high : .moderate,
                headline: "\(best.exerciseName.uppercased()) IS CLIMBING",
                detail: "A non-parametric trend test finds a real upward direction in estimated one-rep max across your recent sessions of this movement. The estimate is the median of five published formulas, and it is only computed for sets of 12 reps or fewer, where those formulas actually hold.",
                evidence: [
                    InsightEvidence("Change", Formatting.signed(best.changeKg, places: 1, unit: "kg"),
                                    context: best.changePercent.map { Formatting.signed($0, places: 1, unit: "%") }),
                    InsightEvidence("Per session",
                                    Formatting.signed(best.slopePerSession, places: 2, unit: "kg")),
                    InsightEvidence("Sessions", "\(best.sessionsConsidered)"),
                ],
                sources: context.sources,
                series: seriesFor(trackingKey: best.trackingKey, progress: context.exerciseProgress),
                priority: 58
            ))
        }

        // A lopsided ratio, only where both sides have real work.
        for ratio in context.balanceRatios {
            guard ratio.hasEnoughData, ratio.isBalanced == false,
                  let value = ratio.ratio, let lighter = ratio.lighterSide else { continue }
            insights.append(HealthInsight(
                id: "strength-balance-\(ratio.name)",
                kind: .strength,
                tone: .neutral,
                confidence: .moderate,
                headline: "\(lighter.uppercased()) IS THE LIGHTER SIDE",
                detail: "\(ratio.explanation) Reference: \(ratio.source).",
                evidence: [
                    InsightEvidence(ratio.numeratorLabel,
                                    "\(Formatting.decimal(ratio.numeratorSets, places: 0)) sets"),
                    InsightEvidence(ratio.denominatorLabel,
                                    "\(Formatting.decimal(ratio.denominatorSets, places: 0)) sets"),
                    InsightEvidence("Ratio", Formatting.decimal(value, places: 2),
                                    context: "reference \(Formatting.decimal(ratio.referenceRange.lowerBound, places: 1)) to \(Formatting.decimal(ratio.referenceRange.upperBound, places: 1))"),
                ],
                sources: context.sources,
                priority: 45
            ))
            break   // one balance note at a time is plenty
        }

        return insights
    }

    // MARK: - Relationships

    static func relationshipInsights(_ context: AnalysisContext) -> [HealthInsight] {
        CorrelationEngine.reportable(context.relationships, limit: 3).map { relationship in
            let correlation = relationship.correlation
            return HealthInsight(
                id: "relationship-\(relationship.id)",
                kind: .relationship,
                tone: .neutral,
                // Even a clean result here is capped at moderate. A single person's
                // observational data cannot support a high-confidence claim about a
                // relationship, however good the arithmetic.
                confidence: correlation.effectiveN >= 20 ? .moderate : .exploratory,
                headline: "\(relationship.predictor.label.uppercased()) TRACKS WITH \(relationship.outcome.label.uppercased())",
                detail: relationship.description + " " + relationship.caveat,
                evidence: [
                    InsightEvidence("Strength",
                                    Formatting.decimal(correlation.coefficient, places: 2),
                                    context: "\(correlation.method.label) correlation, -1 to 1"),
                    InsightEvidence("Days compared", "\(relationship.pairCount)",
                                    context: "\(Formatting.decimal(correlation.effectiveN, places: 0)) independent after correcting for day-to-day carryover"),
                    InsightEvidence("Delay",
                                    correlation.lagDays == 0 ? "same day" : "\(correlation.lagDays) day\(correlation.lagDays == 1 ? "" : "s")"),
                    InsightEvidence("Significance",
                                    "p = \(Formatting.decimal(relationship.adjustedPValue, places: 3))",
                                    context: "adjusted for testing many relationships"),
                ],
                sources: context.sources,
                priority: 50 + correlation.absCoefficient * 10
            )
        }
    }

    // MARK: - Consistency

    static func consistencyInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        guard let consistency = context.consistency else { return [] }

        // A long run of days with no rest.
        if consistency.daysSinceRest >= 10 {
            insights.append(HealthInsight(
                id: "consistency-no-rest",
                kind: .consistency,
                tone: .attention,
                confidence: .high,
                headline: "\(consistency.daysSinceRest) DAYS WITHOUT A FULL REST DAY",
                detail: "Every day in that run has at least one logged session. Rest days are what let load turn into adaptation, and they are also the main thing that lowers training monotony.",
                evidence: [
                    InsightEvidence("Current run", "\(consistency.daysSinceRest) days"),
                    InsightEvidence("Longest run", "\(consistency.longestStreak) days"),
                    InsightEvidence("Sessions per week",
                                    Formatting.decimal(consistency.sessionsPerWeek, places: 1)),
                ],
                sources: context.sources,
                priority: 64
            ))
        }

        // A genuinely consistent stretch, worth acknowledging.
        if consistency.sessionsPerWeek >= 3, consistency.activeDayFraction >= 0.4,
           context.daysOfHistory >= 28 {
            insights.append(HealthInsight(
                id: "consistency-steady",
                kind: .consistency,
                tone: .positive,
                confidence: .high,
                headline: "YOU HAVE BEEN CONSISTENT",
                detail: "Consistency over months is what actually drives every trend in this app, and it is the one input entirely under your control.",
                evidence: [
                    InsightEvidence("Sessions per week",
                                    Formatting.decimal(consistency.sessionsPerWeek, places: 1)),
                    InsightEvidence("Active days",
                                    Formatting.percent(fraction: consistency.activeDayFraction)),
                    InsightEvidence("History", "\(context.daysOfHistory) days"),
                ],
                sources: context.sources,
                priority: 25
            ))
        }

        return insights
    }

    // MARK: - Milestones

    static func milestoneInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []

        // Recent strength records.
        for record in context.strengthRecords.prefix(2) {
            guard let improvement = record.improvementKg, improvement > 0 else { continue }
            insights.append(HealthInsight(
                id: "milestone-strength-\(record.id)",
                kind: .milestone,
                tone: .positive,
                confidence: record.kind == .heaviestSet ? .high : .moderate,
                headline: "NEW \(record.kind.label.uppercased()) ON \(record.exerciseName.uppercased())",
                detail: record.kind == .estimatedOneRepMax
                    ? "This is an estimate from your best set, not a tested single, using the median of five published formulas."
                    : "This is the heaviest working set you have logged for this movement.",
                evidence: [
                    InsightEvidence("New best", Formatting.weight(kilograms: record.valueKg, unit: .kg)),
                    InsightEvidence("Previous",
                                    Formatting.weight(kilograms: record.previousValueKg ?? 0, unit: .kg),
                                    context: Formatting.signed(improvement, places: 1, unit: "kg")),
                    InsightEvidence("When", Formatting.relativeDay(record.date, now: context.now)),
                ],
                sources: context.sources,
                priority: 48
            ))
        }

        // Best VDOT as a running-fitness index.
        if let (vdot, from) = PerformanceAnalysis.bestVDOT(from: context.distanceBests, now: context.now) {
            insights.append(HealthInsight(
                id: "milestone-vdot",
                kind: .milestone,
                tone: .neutral,
                confidence: .moderate,
                headline: "YOUR RUNNING FITNESS INDEX IS \(Int(vdot.rounded()))",
                detail: "VDOT comes from Daniels and Gilbert's equations for the oxygen cost of running and the fraction of maximum sustainable for a given duration. It is a single number summarising running fitness that happens to share units with VO2 max, and it is derived from a real effort rather than estimated from resting values.",
                evidence: [
                    InsightEvidence("VDOT", Formatting.decimal(vdot, places: 1)),
                    InsightEvidence("From", "\(from.distanceName) in \(Formatting.duration(from.timeSeconds))",
                                    context: Formatting.relativeDay(from.date, now: context.now)),
                ],
                sources: context.sources,
                priority: 32
            ))
        }

        return insights
    }

    // MARK: - Data quality

    static func dataQualityInsights(_ context: AnalysisContext) -> [HealthInsight] {
        var insights: [HealthInsight] = []

        // Missing anchors that would sharpen everything downstream.
        if context.profile.maxHeartRate?.isEstimate == true || context.profile.restingHeartRate == nil {
            var missing: [InsightEvidence] = []
            if let maxHR = context.profile.maxHeartRate, maxHR.isEstimate {
                missing.append(InsightEvidence(
                    "Max heart rate",
                    "\(Int(maxHR.value.rounded())) bpm",
                    context: "estimated from your age"
                ))
            }
            if context.profile.restingHeartRate == nil {
                missing.append(InsightEvidence("Resting heart rate", "not set"))
            }
            guard !missing.isEmpty else { return insights }
            insights.append(HealthInsight(
                id: "data-anchors",
                kind: .dataQuality,
                tone: .neutral,
                confidence: .high,
                headline: "SET YOUR HEART-RATE NUMBERS FOR SHARPER ANALYSIS",
                detail: "Training load, heart-rate zones and intensity are all measured against your maximum and resting heart rate. Right now at least one of those is a population estimate from your age rather than your own number, which shifts every figure derived from it.",
                evidence: missing,
                sources: context.sources,
                priority: 20
            ))
        }

        // Garmin sessions that came through Apple Health as envelopes only.
        let garminEnvelopes = context.workouts.filter {
            $0.origin.source == .garmin && $0.heartRateSeries == nil && $0.family == .endurance
        }
        if garminEnvelopes.count >= 3 {
            insights.append(HealthInsight(
                id: "data-garmin-fit",
                kind: .dataQuality,
                tone: .neutral,
                confidence: .high,
                headline: "IMPORT FIT FILES FOR FULL GARMIN DETAIL",
                detail: "Garmin sends the shape of a session to Apple Health but not the detail: no GPS track and no second-by-second heart rate. Those live in the original .fit file, which you can export from Garmin Connect. Importing one unlocks aerobic decoupling, normalized power, heart-rate zones and grade-adjusted pace for that session.",
                evidence: [
                    InsightEvidence("Sessions missing detail", "\(garminEnvelopes.count)"),
                    InsightEvidence("What is missing", "heart-rate series, GPS, power"),
                ],
                sources: [.garmin],
                priority: 22
            ))
        }

        // Lifting sessions with neither heart rate nor RPE can only be scored from duration,
        // which is the weakest method available. Worth saying, because both fixes are easy and
        // the user cannot tell from the outside that their load figures are soft.
        let strengthSessions = context.workouts.filter {
            $0.family == .strength && context.now.timeIntervalSince($0.start) < 60 * 86400
        }
        let unscored = strengthSessions.filter { context.loads[$0.id]?.method == .durationOnly }
        if strengthSessions.count >= 8,
           Double(unscored.count) / Double(strengthSessions.count) > 0.6 {
            insights.append(HealthInsight(
                id: "data-strength-intensity",
                kind: .dataQuality,
                tone: .neutral,
                confidence: .high,
                headline: "LIFTING LOAD IS ESTIMATED FROM DURATION ALONE",
                detail: "Most of your lifting sessions carry neither heart rate nor a perceived-effort rating, so the only thing left to score them by is how long they lasted. That is deliberately conservative and it is the weakest figure in your training load. Two things fix it: wear your watch while you lift, so the session's heart rate reaches Apple Health and merges with the set data, or rate the session in Hevy when you finish it. Either one turns a guess into a measurement.",
                evidence: [
                    InsightEvidence("Sessions affected", "\(unscored.count) of \(strengthSessions.count)",
                                    context: "last 60 days"),
                    InsightEvidence("Currently scored by", "duration and a conservative intensity assumption"),
                    InsightEvidence("Would be scored by", "heart rate, or your own effort rating"),
                ],
                sources: context.sources,
                priority: 24
            ))
        }

        // Explain an empty relationships section rather than showing nothing.
        if context.correlationCoverage.reportableCount == 0, context.daysOfHistory >= 14 {
            insights.append(HealthInsight(
                id: "data-relationships-coverage",
                kind: .dataQuality,
                tone: .neutral,
                confidence: .high,
                headline: "NO RELIABLE PATTERNS YET",
                detail: context.correlationCoverage.summary + " Personal health series drift slowly, so a plain correlation between two of them looks far stronger than it is. This app corrects for that and for the number of relationships tested, which means it reports fewer patterns than a naive search would, and the ones it does report are worth more.",
                evidence: [
                    InsightEvidence("Days of overlapping data", "\(context.correlationCoverage.daysAvailable)"),
                    InsightEvidence("Relationships tested", "\(context.correlationCoverage.pairsTested)"),
                ],
                sources: context.sources,
                priority: 10
            ))
        }

        return insights
    }

    // MARK: - Series helpers

    /// A sparkline for a wellness metric over the last sixty days.
    private static func series(
        for metric: WellnessMetric,
        snapshots: [DailySnapshot],
        baseline: Double?
    ) -> InsightSeries? {
        let points = snapshots
            .suffix(60)
            .compactMap { snapshot -> InsightSeries.Point? in
                guard let value = metric.value(from: snapshot) else { return nil }
                return InsightSeries.Point(date: snapshot.date, value: value)
            }
        guard points.count >= 5 else { return nil }
        return InsightSeries(points: points, baseline: baseline, unit: metric.unit)
    }

    /// A sparkline of estimated one-rep max for one movement.
    private static func seriesFor(
        trackingKey: String,
        progress: [ExerciseProgress]
    ) -> InsightSeries? {
        guard let exercise = progress.first(where: { $0.trackingKey == trackingKey }) else { return nil }
        let points = exercise.sessions.compactMap { point -> InsightSeries.Point? in
            guard let value = point.estimatedOneRepMaxKg else { return nil }
            return InsightSeries.Point(date: point.date, value: value)
        }
        guard points.count >= 4 else { return nil }
        return InsightSeries(points: points, baseline: nil, unit: "kg")
    }
}
