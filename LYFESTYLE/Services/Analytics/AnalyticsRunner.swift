//
//  AnalyticsRunner.swift
//  LYFESTYL
//
//  Runs the whole analysis in one pass, OFF the main actor.
//
//  This matters for responsiveness. A year of training is a few hundred sessions and a few
//  hundred daily snapshots, and the pipeline includes several genuinely quadratic steps:
//  Theil-Sen compares every pair of points, Mann-Kendall does the same, and the mean-maximal
//  curve scans every window at every duration. Running that on the main actor would stall
//  scrolling, which is why every type it touches is `nonisolated` and this is an `actor`.
//
//  The runner is also the single place that decides ORDER, because much of the analysis is
//  a chain: load scores feed the fitness model, the fitness model feeds form, form feeds the
//  correlation search, and everything feeds the insights. Doing it in one place means those
//  dependencies are explicit instead of scattered.
//

import Foundation

// MARK: - Result

/// Everything the UI needs from one analysis pass.
nonisolated struct AnalysisResult: Sendable {
    var insights: [HealthInsight]
    var context: AnalysisContext
    /// When this pass ran.
    var computedAt: Date
    /// How long it took, kept so a slow device can be diagnosed rather than guessed at.
    var duration: TimeInterval

    var isEmpty: Bool { context.workouts.isEmpty && context.snapshots.isEmpty }

    // Convenience passthroughs the UI reaches for constantly.
    var fitness: [FitnessPoint] { context.fitness }
    var loadRamp: LoadRamp { context.loadRamp }
    var weeks: [TrainingWeek] { context.weeks }
    var baselines: [WellnessMetric: MetricBaseline] { context.baselines }
    var readiness: ReadinessRead { context.readiness }
    var sleep: SleepSummary { context.sleep }
    var muscleVolume: [MuscleVolume] { context.muscleVolume }
    var exerciseProgress: [ExerciseProgress] { context.exerciseProgress }
    var distanceBests: [DistanceBest] { context.distanceBests }
    var relationships: [DiscoveredRelationship] { context.relationships }

    /// Current form, when the model has enough history.
    var currentForm: Double? {
        context.loadRamp.isEstablished ? context.fitness.last?.form : nil
    }

    var currentFitness: Double? {
        context.loadRamp.isEstablished ? context.fitness.last?.fitness : nil
    }

    /// Load per session, for the workout list.
    func load(for workoutID: String) -> TrainingLoadResult? { context.loads[workoutID] }
    func zones(for workoutID: String) -> ZoneDistribution? { context.zones[workoutID] }
}

// MARK: - Runner

/// An actor so the work provably happens off the main thread and one pass cannot overlap
/// another.
actor AnalyticsRunner {

    /// How far back the analysis looks. Long enough for the 42-day fitness constant to be
    /// well established and for a season's trend to be visible.
    static let historyDays = 400

    /// Run the full pipeline.
    ///
    /// Deliberately takes plain values rather than the store, so it can never touch mutable
    /// shared state and is trivially testable.
    func run(
        workouts: [UnifiedWorkout],
        snapshots: [DailySnapshot],
        profile: ProfileSnapshot,
        sleepTargetHours: Double?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalysisResult {
        let started = Date()

        // Trim to the analysis window and put both series in chronological order, which every
        // downstream step assumes.
        let cutoff = calendar.date(byAdding: .day, value: -Self.historyDays, to: now) ?? now
        let sessions = workouts
            .filter { $0.start >= cutoff && $0.start <= now.addingTimeInterval(86400) }
            .sorted { $0.start < $1.start }
        let days = snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        // 1. Score every session. Everything about load depends on this.
        var loads: [String: TrainingLoadResult] = [:]
        var zones: [String: ZoneDistribution] = [:]
        for session in sessions {
            // A lifting session with no heart rate can still be scored from the set-level RPEs
            // the user logged, so give the scorer that before it falls back to duration.
            var scored = session
            if scored.perceivedEffort == nil, let strength = scored.strength,
               let implied = TrainingLoad.impliedSessionRPE(for: strength) {
                scored.perceivedEffort = implied
            }
            if let result = TrainingLoad.score(scored, profile: profile) {
                loads[session.id] = result
            }
            // Zone occupancy needs a heart-rate series AND known zone boundaries. A Garmin
            // session read from Apple Health has no series, so it simply has no zones, which
            // is why the intensity distribution reports its own coverage.
            if let series = session.heartRateSeries,
               let distribution = TrainingLoad.zoneDistribution(heartRateSeries: series, profile: profile) {
                zones[session.id] = distribution
            }
        }

        // 2. Daily load series, gap-free with explicit rest-day zeros, then the two-component
        //    fitness model over it.
        let dailyLoads = FitnessModel.dailyLoadSeries(
            workouts: sessions, loads: loads, through: now, calendar: calendar
        )
        let fitness = FitnessModel.run(dailyLoads: dailyLoads)
        let loadRamp = FitnessModel.loadRamp(dailyLoads: dailyLoads)
        let weeks = FitnessModel.weeks(workouts: sessions, loads: loads, zones: zones, calendar: calendar)
        let consistency = FitnessModel.consistency(dailyLoads: dailyLoads)
        let intensity = FitnessModel.intensityDistribution(Array(zones.values))

        // 3. Recovery baselines and the readiness read.
        let baselines = RecoveryAnalysis.baselines(snapshots: days, now: now, calendar: calendar)
        let sleep = RecoveryAnalysis.sleepSummary(
            snapshots: days, targetHours: sleepTargetHours, now: now, calendar: calendar
        )
        let form = loadRamp.isEstablished ? fitness.last?.form : nil
        let readiness = RecoveryAnalysis.readiness(
            snapshots: days, baselines: baselines, form: form, now: now, calendar: calendar
        )
        let rhrShift = RecoveryAnalysis.restingHeartRateShift(
            snapshots: days, now: now, calendar: calendar
        )

        // 4. Strength.
        let progress = StrengthAnalysis.exerciseProgress(from: sessions)
        let muscleVolume = StrengthAnalysis.muscleVolume(
            workouts: sessions, now: now, calendar: calendar
        )
        let muscleSets = StrengthAnalysis.musclesSets(workouts: sessions, now: now, calendar: calendar)
        let balance = StrengthAnalysis.balanceRatios(muscleVolume, muscleSets: muscleSets)
        let plateaus = StrengthAnalysis.plateauChecks(progress)
        let records = StrengthAnalysis.recentRecords(progress, now: now)

        // 5. Endurance.
        let bests = PerformanceAnalysis.distanceBests(workouts: sessions)
        let predictions = PerformanceAnalysis.predictions(from: bests, now: now)

        // 6. The correlation search, which needs form and load and therefore comes last.
        let aligned = CorrelationEngine.alignedSeries(
            snapshots: days, workouts: sessions, loads: loads, fitness: fitness, calendar: calendar
        )
        let relationships = aligned.map { CorrelationEngine.search($0) } ?? []
        let coverage = CorrelationEngine.coverage(aligned, relationships: relationships)

        let context = AnalysisContext(
            workouts: sessions,
            snapshots: days,
            profile: profile,
            loads: loads,
            zones: zones,
            fitness: fitness,
            loadRamp: loadRamp,
            weeks: weeks,
            consistency: consistency,
            baselines: baselines,
            sleep: sleep,
            readiness: readiness,
            exerciseProgress: progress,
            muscleVolume: muscleVolume,
            balanceRatios: balance,
            plateaus: plateaus,
            strengthRecords: records,
            distanceBests: bests,
            racePredictions: predictions,
            relationships: relationships,
            correlationCoverage: coverage,
            intensity: intensity,
            restingHeartRateShift: rhrShift,
            now: now
        )

        return AnalysisResult(
            insights: InsightBuilder.build(context),
            context: context,
            computedAt: now,
            duration: Date().timeIntervalSince(started)
        )
    }

    /// Anchors the data itself reveals, folded back into the athlete profile so the next pass
    /// is sharper. Kept here because it is derived from the same session set.
    func observedAnchors(
        workouts: [UnifiedWorkout],
        snapshots: [DailySnapshot]
    ) -> (maxHeartRate: Double?, restingHeartRate: Double?, thresholdPaceSecPerKm: Double?, bodyMassKg: Double?) {
        // The highest heart rate ever actually recorded in a session beats any age formula.
        let observedMax = workouts.compactMap(\.maxHeartRate)
            .filter { ProfileSnapshot.plausibleMaxHeartRate.contains($0) }
            .max()

        // Resting heart rate: the median of the recent daily values, which is more stable
        // than the single most recent reading.
        let recentResting = snapshots.suffix(30).compactMap(\.restingHeartRate)
            .filter { ProfileSnapshot.plausibleRestingHeartRate.contains($0) }
        let observedResting = Stats.median(recentResting)

        // Threshold pace: estimated from the best recent sustained effort.
        //
        // Threshold is conventionally the pace sustainable for roughly an hour. Rather than
        // assume the user has raced for an hour, this takes their best effort of at least
        // twenty minutes and scales it to sixty via Riegel, which is the same relationship
        // used for race prediction.
        var observedThresholdPace: Double?
        let bests = PerformanceAnalysis.distanceBests(workouts: workouts)
        if let base = bests
            .filter({ $0.isCloseToNominal && $0.timeSeconds >= 1200 })
            .min(by: { $0.pacePerKm < $1.pacePerKm }) {
            // Scale the effort out to sixty minutes. Riegel says T2 = T1 (D2/D1)^1.06, so
            // setting T2 = 3600 and solving for D2 gives D2 = D1 (3600/T1)^(1/1.06). The pace
            // over that distance is the one-hour pace, which is the conventional definition
            // of threshold.
            let ratio = pow(3600 / base.timeSeconds, 1 / RacePrediction.riegelExponent)
            let hourDistance = base.actualDistanceMeters * ratio
            if hourDistance > 3000 {
                observedThresholdPace = 3600 / (hourDistance / 1000)
            }
        }

        let observedMass = snapshots.suffix(14).compactMap(\.bodyMassKg).last

        return (observedMax, observedResting, observedThresholdPace, observedMass)
    }
}
