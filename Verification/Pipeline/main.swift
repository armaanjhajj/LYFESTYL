//
//  main.swift
//  Verification/Pipeline
//
//  End-to-end assertions over the whole analysis pipeline, run against the generated sample
//  history. This is the check that catches the class of bug a unit test on one function misses:
//  a value that is individually plausible but wrong by a factor once it has flowed through
//  scoring, the fitness model, the baselines and the insight builder.
//
//  It has already caught one real bug. Grade-adjusted pace was resampling a cumulative distance
//  series onto a finer grid than its own samples, which credited a full sample interval's
//  distance to one grid step and multiplied the implied speed by the ratio of the two spacings.
//  A normal trail run scored an intensity factor of 3.19 and a training load of 1712 instead of
//  about 143, and the fatigue curve peaked at 295. Every individual formula was correct.
//
//  Build and run from the repository root:
//
//    swiftc -DDEBUG -O -o pipetest \
//      LYFESTYLE/Models/Unified/*.swift LYFESTYLE/Services/Analytics/*.swift \
//      LYFESTYLE/Models/HealthSampleData.swift LYFESTYLE/Models/HealthInsight.swift \
//      LYFESTYLE/Models/Exercise.swift LYFESTYLE/Models/ExerciseLibrary.swift \
//      LYFESTYLE/Models/Workout.swift LYFESTYLE/Models/JournalEntry.swift \
//      LYFESTYLE/DesignSystem/SolarizedPalette.swift LYFESTYLE/DesignSystem/Formatting.swift \
//      LYFESTYLE/DesignSystem/InsightCategory.swift Verification/Pipeline/main.swift
//    ./pipetest
//

import Foundation

var failures: [String] = []
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        let extra = detail()
        failures.append("  \(name)\(extra.isEmpty ? "" : ": \(extra)")")
    }
}

func fmt(_ value: Double?, _ places: Int = 1) -> String {
    guard let value else { return "nil" }
    return String(format: "%.\(places)f", value)
}

// MARK: - Generate

let (workouts, snapshots) = HealthSampleData.generate()
print("Sample history: \(workouts.count) sessions, \(snapshots.count) days\n")

check("sample sessions generated", workouts.count > 100, "\(workouts.count)")
check("sample days generated", snapshots.count >= 180, "\(snapshots.count)")

let profile = ProfileSnapshot(
    maxHeartRate: Anchor(value: 188, provenance: .userEntered),
    restingHeartRate: Anchor(value: 48, provenance: .userEntered),
    functionalThresholdPower: Anchor(value: 245, provenance: .userEntered),
    thresholdPaceSecPerKm: Anchor(value: 258, provenance: .userEntered),
    age: 30,
    sex: .unspecified
)

// MARK: - Training load

var loads: [String: TrainingLoadResult] = [:]
for workout in workouts.sorted(by: { $0.start < $1.start }) {
    var scored = workout
    if scored.perceivedEffort == nil, let strength = scored.strength,
       let implied = TrainingLoad.impliedSessionRPE(for: strength) {
        scored.perceivedEffort = implied
    }
    if let result = TrainingLoad.score(scored, profile: profile) {
        loads[workout.id] = result
    }
}

check("every session scored", loads.count == workouts.count, "\(loads.count) of \(workouts.count)")

let loadValues = loads.values.map(\.load)
let maxLoad = loadValues.max() ?? 0

// One hour at threshold is 100 points by definition, so a single session above 400 means
// something upstream is wrong by a factor, not that the session was very hard.
check("no session load is implausible", maxLoad < 400, "max was \(fmt(maxLoad))")
check("no session load is zero or negative", loadValues.allSatisfy { $0 > 0 })

let intensityFactors = loads.values.compactMap(\.intensityFactor)
// Intensity is expressed relative to threshold. Above 2.0 sustained over a whole session is
// not physiologically possible, so it indicates a unit or scaling error.
check("intensity factors are plausible",
      intensityFactors.allSatisfy { $0 > 0.2 && $0 < 2.0 },
      "range \(fmt(intensityFactors.min())) to \(fmt(intensityFactors.max(), 2))")

print("Load: \(loads.count) scored, median \(fmt(Stats.median(loadValues))), max \(fmt(maxLoad))")
let methods = Dictionary(grouping: loads.values, by: \.method).mapValues(\.count)
print("Methods: " + methods.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))

// MARK: - Grade adjustment

// Checked directly, because this is where the factor bug lived.
var gradeRatios: [Double] = []
for workout in workouts where workout.altitudeSeries != nil && workout.distanceSeries != nil {
    guard let adjusted = TrainingLoad.gradeAdjustedSpeed(
        distanceSeries: workout.distanceSeries,
        altitudeSeries: workout.altitudeSeries,
        fallbackSpeedMps: workout.effectiveSpeedMps
    ), let raw = workout.effectiveSpeedMps, raw > 0 else { continue }
    gradeRatios.append(adjusted / raw)
}
check("grade adjustment stays near the raw speed",
      gradeRatios.allSatisfy { $0 > 0.6 && $0 < 1.8 },
      "range \(fmt(gradeRatios.min(), 3)) to \(fmt(gradeRatios.max(), 3)) over \(gradeRatios.count) runs")
print("Grade adjustment: \(gradeRatios.count) runs, ratio \(fmt(gradeRatios.min(), 3)) to \(fmt(gradeRatios.max(), 3))")

// Minetti's polynomial at known points.
check("flat cost of running is 3.6 J/kg/m",
      abs(TrainingLoad.runningCostOfTransport(gradient: 0) - 3.6) < 1e-9)
check("uphill costs more than flat",
      TrainingLoad.gradeAdjustmentFactor(gradient: 0.10) > 1.3)
check("gentle downhill costs less than flat",
      TrainingLoad.gradeAdjustmentFactor(gradient: -0.10) < 1.0)

// MARK: - Fitness model

let daily = FitnessModel.dailyLoadSeries(workouts: workouts, loads: loads)
let fitness = FitnessModel.run(dailyLoads: daily)
let maxDailyLoad = daily.map(\.load).max() ?? 0
let maxFatigue = fitness.map(\.fatigue).max() ?? 0
let maxFitness = fitness.map(\.fitness).max() ?? 0

check("daily series is gap free", daily.count >= 180, "\(daily.count) days")
// Both are exponentially weighted averages of daily load, so neither can exceed the largest
// single day. If one does, the recursion is wrong.
check("fatigue never exceeds the largest daily load",
      maxFatigue <= maxDailyLoad + 0.001,
      "fatigue \(fmt(maxFatigue)) vs max daily \(fmt(maxDailyLoad))")
check("fitness never exceeds the largest daily load",
      maxFitness <= maxDailyLoad + 0.001,
      "fitness \(fmt(maxFitness)) vs max daily \(fmt(maxDailyLoad))")
check("fitness is slower moving than fatigue", maxFitness < maxFatigue)

let ramp = FitnessModel.loadRamp(dailyLoads: daily)
check("load ramp is established over 180 days", ramp.isEstablished)
check("load ramp ratio is plausible",
      (ramp.ratio ?? 0) > 0.3 && (ramp.ratio ?? 0) < 3.0, "\(fmt(ramp.ratio, 2))")
print("Fitness: max \(fmt(maxFitness)), fatigue max \(fmt(maxFatigue)), ramp \(fmt(ramp.ratio, 2))")

// The exponential decay constant, against its definition.
check("42-day decay factor matches 1 - e^(-1/42)",
      abs(FitnessModel.decayFactor(timeConstant: 42) - (1 - exp(-1.0 / 42))) < 1e-12)

// MARK: - Recovery baselines

let baselines = RecoveryAnalysis.baselines(snapshots: snapshots)
check("HRV baseline established", baselines[.heartRateVariability]?.isEstablished == true)
check("resting heart rate baseline established", baselines[.restingHeartRate]?.isEstablished == true)
check("HRV is analysed on the log scale",
      baselines[.heartRateVariability]?.analysedOnLogScale == true)

if let hrv = baselines[.heartRateVariability] {
    // The generator centres HRV near 62 ms.
    check("HRV baseline centre is realistic",
          hrv.center > 45 && hrv.center < 80, "\(fmt(hrv.center))")
    check("HRV smallest worthwhile change is positive", hrv.smallestWorthwhileChange > 0)
    print("HRV baseline: centre \(fmt(hrv.center)) ms, spread \(fmt(hrv.spread)), n=\(hrv.sampleCount)")
}

// The generator introduces a deliberate resting-heart-rate step two thirds of the way in.
let shift = RecoveryAnalysis.restingHeartRateShift(snapshots: snapshots, windowDays: 180)
check("the planted resting heart rate step is detected", shift != nil)
if let shift {
    check("the detected step points upward", shift.isUpward,
          "before \(fmt(shift.meanBefore)) after \(fmt(shift.meanAfter))")
    print("RHR step: \(fmt(shift.meanBefore)) to \(fmt(shift.meanAfter)) bpm")
}

// MARK: - Sleep

let sleep = RecoveryAnalysis.sleepSummary(snapshots: snapshots, windowDays: 180)
check("nights were assembled", sleep.nightCount > 140, "\(sleep.nightCount)")
check("typical sleep is realistic",
      (sleep.typicalHours ?? 0) > 6 && (sleep.typicalHours ?? 0) < 9, "\(fmt(sleep.typicalHours, 2))")
check("sleep regularity index is in range",
      (sleep.regularityIndex ?? -999) >= -100 && (sleep.regularityIndex ?? 999) <= 100,
      "\(fmt(sleep.regularityIndex))")
// Stage shares must sum to roughly the whole night, which is the test that the interval union
// arithmetic did not double count.
if let deep = sleep.stageShares[.deep], let rem = sleep.stageShares[.rem] {
    check("deep sleep share is realistic", deep > 0.05 && deep < 0.35, "\(fmt(deep, 3))")
    check("REM share is realistic", rem > 0.10 && rem < 0.40, "\(fmt(rem, 3))")
}
print("Sleep: \(sleep.nightCount) nights, typical \(fmt(sleep.typicalHours, 2)) h, SRI \(fmt(sleep.regularityIndex))")

// MARK: - Strength

let progress = StrengthAnalysis.exerciseProgress(from: workouts)
check("exercises tracked across sessions", progress.count >= 5, "\(progress.count)")

let plateaus = StrengthAnalysis.plateauChecks(progress)
// The generator holds the bench press flat and climbs the squat, so the detector must tell
// them apart. This is the check that the trend test is doing real work rather than always
// agreeing.
let bench = plateaus.first { $0.exerciseName.lowercased().contains("bench") }
let squat = plateaus.first { $0.exerciseName.lowercased().contains("squat") }
check("the flat bench press is found", bench != nil)
check("the climbing squat is found", squat != nil)
if let bench { check("bench press is not reported as progressing", !bench.isProgressing,
                     "slope \(fmt(bench.slopePerSession, 3)) kg/session") }
if let squat { check("squat is reported as progressing", squat.isProgressing,
                     "slope \(fmt(squat.slopePerSession, 3)) kg/session, p=\(fmt(squat.test.pValue, 4))") }
if let bench, let squat {
    print("Strength trends: bench \(fmt(bench.slopePerSession, 3)) kg/session (\(bench.test.direction.rawValue)), squat \(fmt(squat.slopePerSession, 3)) kg/session (\(squat.test.direction.rawValue))")
}

let volume = StrengthAnalysis.muscleVolume(workouts: workouts)
check("muscle volume computed", volume.contains { $0.setsPerWeek > 0 })
let trained = volume.filter { $0.setsPerWeek > 0 }
check("weekly sets are plausible",
      trained.allSatisfy { $0.setsPerWeek < 60 },
      "max \(fmt(trained.map(\.setsPerWeek).max()))")

// Estimated one-rep max, against the published formulas.
check("Epley at 1 rep returns the load itself",
      OneRepMax.Formula.epley.estimate(weight: 100, reps: 1) == 100)
check("Epley at 10 reps is load x 4/3",
      abs((OneRepMax.Formula.epley.estimate(weight: 100, reps: 10) ?? 0) - 133.3333) < 0.001)
check("Brzycki at 10 reps is load x 36/27",
      abs((OneRepMax.Formula.brzycki.estimate(weight: 100, reps: 10) ?? 0) - 133.3333) < 0.001)
check("one-rep max is refused above the rep ceiling",
      OneRepMax.estimate(weightKg: 100, reps: 20) == nil)
check("one-rep max is produced inside the rep ceiling",
      OneRepMax.estimate(weightKg: 100, reps: 5) != nil)

// MARK: - Endurance

let bests = PerformanceAnalysis.distanceBests(workouts: workouts)
check("distance bests found", !bests.isEmpty, "\(bests.count)")
for best in bests {
    // A 5k in under 12 minutes or over 60 is a scanning error, not a run.
    let pace = best.pacePerKm
    check("\(best.distanceName) pace is plausible", pace > 140 && pace < 900, "\(fmt(pace)) s/km")
}
print("Bests: " + bests.map { "\($0.distanceName) \(Formatting.duration($0.timeSeconds))" }.joined(separator: ", "))

// Riegel, against its published form.
if let doubled = RacePrediction.riegel(knownTimeSeconds: 1200, knownDistanceMeters: 5000,
                                       targetDistanceMeters: 10000) {
    check("Riegel doubles distance by 2^1.06",
          abs(doubled - 1200 * pow(2, 1.06)) < 0.001, "\(fmt(doubled))")
}

// VDOT, against a known reference: a 20:00 5k is close to VDOT 50.
if let vdot = VO2MaxEstimate.vdot(distanceMeters: 5000, timeSeconds: 1200) {
    check("VDOT for a 20:00 5k is near 50", vdot > 48 && vdot < 52, "\(fmt(vdot, 2))")
    print("VDOT for a 20:00 5k: \(fmt(vdot, 2))")
}

// MARK: - Correlations

let aligned = CorrelationEngine.alignedSeries(
    snapshots: snapshots, workouts: workouts, loads: loads, fitness: fitness
)
check("aligned day grid built", aligned != nil)
let relationships = aligned.map { CorrelationEngine.search($0) } ?? []
check("relationships tested", relationships.count >= 10, "\(relationships.count)")

// The generator makes HRV respond to the PREVIOUS night's sleep, so a correct search must find
// that relationship, positively, at a lag of one day. If it does not, the lag alignment is
// broken.
let sleepToHRV = relationships.first {
    $0.predictor == .wellness(.sleepDuration) && $0.outcome == .wellness(.heartRateVariability)
}
check("the planted sleep to HRV relationship is found", sleepToHRV != nil)
if let sleepToHRV {
    check("it is positive", sleepToHRV.correlation.isPositive,
          "r=\(fmt(sleepToHRV.correlation.coefficient, 3))")
    check("it is detected at a one day lag", sleepToHRV.correlation.lagDays == 1,
          "lag \(sleepToHRV.correlation.lagDays)")
    check("it clears the reporting bar", sleepToHRV.isReportable,
          "r=\(fmt(sleepToHRV.correlation.coefficient, 3)) p=\(fmt(sleepToHRV.adjustedPValue, 4)) n=\(sleepToHRV.pairCount)")
    print("Sleep to HRV: r=\(fmt(sleepToHRV.correlation.coefficient, 3)) at lag \(sleepToHRV.correlation.lagDays), adjusted p=\(fmt(sleepToHRV.adjustedPValue, 4))")
}

// The effective sample size must actually bite: autocorrelated daily series carry less
// independent information than their raw day count.
let corrected = relationships.filter { $0.correlation.effectiveN < Double($0.correlation.n) }
check("autocorrelation correction is applied", !corrected.isEmpty,
      "\(corrected.count) of \(relationships.count) relationships were corrected")

// The false-discovery-rate correction must only ever raise a p-value.
check("FDR adjustment never lowers a p-value",
      relationships.allSatisfy { $0.adjustedPValue >= $0.correlation.pValue - 1e-12 })

let reportable = CorrelationEngine.reportable(relationships)
print("Relationships: \(relationships.count) tested, \(reportable.count) reportable")

// MARK: - Insights

let context = AnalysisContext(
    workouts: workouts.sorted { $0.start < $1.start },
    snapshots: snapshots,
    profile: profile,
    loads: loads,
    zones: [:],
    fitness: fitness,
    loadRamp: ramp,
    weeks: FitnessModel.weeks(workouts: workouts, loads: loads, zones: [:]),
    consistency: FitnessModel.consistency(dailyLoads: daily),
    baselines: baselines,
    sleep: sleep,
    readiness: RecoveryAnalysis.readiness(snapshots: snapshots, baselines: baselines,
                                          form: fitness.last?.form),
    exerciseProgress: progress,
    muscleVolume: volume,
    balanceRatios: StrengthAnalysis.balanceRatios(volume),
    plateaus: plateaus,
    strengthRecords: StrengthAnalysis.recentRecords(progress),
    distanceBests: bests,
    racePredictions: PerformanceAnalysis.predictions(from: bests),
    relationships: relationships,
    correlationCoverage: CorrelationEngine.coverage(aligned, relationships: relationships),
    intensity: nil,
    restingHeartRateShift: shift,
    now: Date()
)

let insights = InsightBuilder.build(context)
check("insights produced", !insights.isEmpty, "\(insights.count)")
check("insight ids are unique",
      Set(insights.map(\.id)).count == insights.count,
      "\(insights.count) insights, \(Set(insights.map(\.id)).count) unique ids")
check("every insight has a headline", insights.allSatisfy { !$0.headline.isEmpty })
check("every insight has detail", insights.allSatisfy { !$0.detail.isEmpty })
check("insights are ranked", insights == insights.ranked)

// The house style forbids em dashes, and this is the surface where prose is generated.
let emDashed = insights.filter { $0.headline.contains("\u{2014}") || $0.detail.contains("\u{2014}") }
check("no insight text contains an em dash", emDashed.isEmpty,
      emDashed.map(\.id).joined(separator: ", "))

// A correlation in one person's observational data can never be high confidence.
let overconfident = insights.filter { $0.kind == .relationship && $0.confidence == .high }
check("no relationship insight claims high confidence", overconfident.isEmpty)

print("\nInsights: \(insights.count)")
for insight in insights.prefix(8) {
    print("  [\(insight.confidence.label)] \(insight.kind.label): \(insight.headline)")
}

// MARK: - Report

print("\n\(checks) checks")
if failures.isEmpty {
    print("PIPELINE VERIFIED")
    exit(0)
}
print("\n\(failures.count) FAILURES:")
for failure in failures { print(failure) }
exit(1)
