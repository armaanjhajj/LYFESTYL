//
//  StrengthAnalysis.swift
//  LYFESTYL
//
//  What the lifting data actually says: how much each muscle is getting, whether the main
//  lifts are moving, and where the programme is lopsided.
//
//  The guiding constraint is that estimated one-rep max is only trustworthy in a narrow
//  band. Every published formula is fitted on sets of roughly one to ten reps, and beyond
//  that it is extrapolation dressed up as arithmetic: a set of twenty at bodyweight does
//  not tell you a single-rep maximum. So `estimateOneRepMax` refuses above a rep ceiling
//  rather than returning a confident wrong number.
//
//  Weekly set counts are compared against the dose-response range reported in the
//  hypertrophy literature (Schoenfeld and colleagues found more sets produced more growth
//  across roughly ten to twenty hard sets per muscle per week, with returns flattening
//  after). That range is offered as CONTEXT, never as a target the user is failing.
//

import Foundation

// MARK: - Estimated one-rep max

nonisolated enum OneRepMax {

    /// Which published formula to use. They disagree most at high reps, which is precisely
    /// where none of them should be trusted.
    enum Formula: String, CaseIterable, Sendable {
        /// Epley (1985): 1RM = w x (1 + reps / 30). The most widely used.
        case epley
        /// Brzycki (1993): 1RM = w x 36 / (37 - reps). Closer than Epley at low reps,
        /// and undefined at 37 reps, where its denominator reaches zero.
        case brzycki
        /// Lombardi (1989): 1RM = w x reps^0.10.
        case lombardi
        /// Mayhew et al. (1992): 1RM = 100 w / (52.2 + 41.9 e^(-0.055 reps)).
        case mayhew
        /// O'Conner et al. (1989): 1RM = w x (1 + 0.025 reps).
        case oconner

        var label: String {
            switch self {
            case .epley:    "Epley"
            case .brzycki:  "Brzycki"
            case .lombardi: "Lombardi"
            case .mayhew:   "Mayhew"
            case .oconner:  "O'Conner"
            }
        }

        func estimate(weight: Double, reps: Int) -> Double? {
            let r = Double(reps)
            guard weight > 0, reps >= 1 else { return nil }
            if reps == 1 { return weight }
            switch self {
            case .epley:    return weight * (1 + r / 30)
            case .brzycki:
                guard r < 37 else { return nil }
                return weight * 36 / (37 - r)
            case .lombardi: return weight * pow(r, 0.10)
            case .mayhew:   return 100 * weight / (52.2 + 41.9 * exp(-0.055 * r))
            case .oconner:  return weight * (1 + 0.025 * r)
            }
        }
    }

    /// The highest rep count at which an estimate is reported.
    ///
    /// The formulas are fitted on low-rep sets and diverge sharply beyond about ten, so
    /// this refuses rather than extrapolating. A set of fifteen simply does not contain the
    /// information needed to estimate a single-rep maximum.
    static let maximumReps = 12

    /// Estimated one-rep max in kilograms, as the MEDIAN of the applicable formulas.
    ///
    /// Using the median rather than one formula is deliberate: the formulas disagree by
    /// several percent and there is no consensus on a winner, so the median is both more
    /// robust and more honest than picking a favourite.
    static func estimate(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps <= maximumReps else { return nil }
        let estimates = Formula.allCases.compactMap { $0.estimate(weight: weightKg, reps: reps) }
        return Stats.median(estimates)
    }

    /// Best estimate across a set of sets, which is what a session's top single is.
    static func best(in sets: [StrengthSet]) -> Double? {
        sets.compactMap { set -> Double? in
            guard set.isWorkingSet, let weight = set.weightKg, let reps = set.reps else { return nil }
            return estimate(weightKg: weight, reps: reps)
        }.max()
    }

    /// Load for a target rep count, inverting Epley. Used to describe what a change in
    /// estimated maximum means in working weight.
    static func workingWeight(oneRepMaxKg: Double, targetReps: Int) -> Double? {
        guard oneRepMaxKg > 0, targetReps >= 1, targetReps <= maximumReps else { return nil }
        return oneRepMaxKg / (1 + Double(targetReps) / 30)
    }

    /// The percentage of one-rep max that an RPE and rep count implies, from the
    /// RPE-to-percentage tables used in Reactive Training Systems and by Helms.
    ///
    /// Only the well-populated part of the table is covered (reps 1 to 12, RPE 6 to 10);
    /// outside it, nil.
    static func percentOfMax(reps: Int, rpe: Double) -> Double? {
        guard reps >= 1, reps <= 12, rpe >= 6, rpe <= 10 else { return nil }
        // Rows are RPE 10 down to 6 in half-point steps; columns are reps 1 to 12.
        let table: [[Double]] = [
            [100.0, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0], // 10
            [97.8, 93.9, 90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7],  // 9.5
            [95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0, 65.3],  // 9
            [93.9, 90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7, 64.0],  // 8.5
            [92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0, 65.3, 62.6],  // 8
            [90.7, 87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7, 64.0, 61.3],  // 7.5
            [89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0, 65.3, 62.6, 59.9],  // 7
            [87.8, 85.0, 82.4, 79.9, 77.4, 75.1, 72.3, 69.4, 66.7, 64.0, 61.3, 58.6],  // 6.5
            [86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 70.7, 68.0, 65.3, 62.6, 59.9, 57.2],  // 6
        ]
        let rowIndex = Int(((10 - rpe) * 2).rounded())
        guard rowIndex >= 0, rowIndex < table.count else { return nil }
        return table[rowIndex][reps - 1]
    }
}

// MARK: - Per-exercise history

/// How one movement has moved over time.
nonisolated struct ExerciseProgress: Identifiable, Hashable, Sendable {
    /// Stable key across sessions, surviving a rename.
    var trackingKey: String
    var name: String
    /// Sessions containing this movement, oldest first.
    var sessions: [Point]
    var systems: [BodySystem]

    struct Point: Hashable, Sendable, Identifiable {
        var date: Date
        var estimatedOneRepMaxKg: Double?
        var topSetWeightKg: Double?
        var volumeLoadKg: Double?
        var workingSets: Int
        var totalReps: Int?
        var averageRPE: Double?
        var id: Date { date }
    }

    var id: String { trackingKey }

    var sessionCount: Int { sessions.count }
    var lastPerformed: Date? { sessions.last?.date }

    /// Best estimated one-rep max ever recorded, and when.
    var bestOneRepMax: (value: Double, date: Date)? {
        let candidates = sessions.compactMap { point -> (Double, Date)? in
            guard let value = point.estimatedOneRepMaxKg else { return nil }
            return (value, point.date)
        }
        guard let best = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        return (best.0, best.1)
    }

    /// The most recent estimated one-rep max.
    var currentOneRepMax: Double? {
        sessions.reversed().compactMap(\.estimatedOneRepMaxKg).first
    }

    /// Robust trend in estimated one-rep max, in kilograms per session.
    ///
    /// Uses Theil-Sen rather than least squares so a single mistimed heavy single or a
    /// deload week cannot dominate the slope, and Mann-Kendall to decide whether the trend
    /// is real at all. Both are non-parametric, which suits a short, noisy series.
    var oneRepMaxTrend: (slopePerSession: Double, test: Stats.TrendTest)? {
        let values = sessions.compactMap(\.estimatedOneRepMaxKg)
        guard values.count >= 8, let test = Stats.mannKendall(values) else { return nil }
        let slope = Stats.theilSenTrend(values)?.slope ?? 0
        return (slope, test)
    }

    /// Days between the two most recent sessions of this movement.
    var daysSinceLastPerformed: Int? {
        guard let last = lastPerformed else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}

// MARK: - Muscle-level volume

/// Weekly hard sets for one muscle or region.
nonisolated struct MuscleVolume: Identifiable, Hashable, Sendable {
    var system: BodySystem
    /// Credited hard sets per week, averaged over the window.
    var setsPerWeek: Double
    /// Total credited sets across the window.
    var totalSets: Double
    /// Distinct days this region was trained.
    var sessionCount: Int
    var lastTrained: Date?
    /// Trend in weekly sets, robust slope in sets per week per week.
    var weeklyTrend: Double?

    var id: String { system.rawValue }

    /// Weekly hard sets per muscle group reported in the hypertrophy dose-response
    /// literature. Presented as CONTEXT, never as a target: the reviews describe a
    /// population dose-response, not a prescription for one person.
    static let literatureRange: ClosedRange<Double> = 10...20

    /// Where this sits relative to that published range.
    enum Standing: String, Sendable {
        case belowRange, withinRange, aboveRange, untrained

        var label: String {
            switch self {
            case .belowRange:  "BELOW THE USUAL RANGE"
            case .withinRange: "IN THE USUAL RANGE"
            case .aboveRange:  "ABOVE THE USUAL RANGE"
            case .untrained:   "NOT TRAINED"
            }
        }
    }

    var standing: Standing {
        guard setsPerWeek > 0 else { return .untrained }
        if setsPerWeek < Self.literatureRange.lowerBound { return .belowRange }
        if setsPerWeek > Self.literatureRange.upperBound { return .aboveRange }
        return .withinRange
    }

    var daysSinceLastTrained: Int? {
        guard let lastTrained else { return nil }
        return Calendar.current.dateComponents([.day], from: lastTrained, to: Date()).day
    }
}

// MARK: - Balance ratios

/// An agonist-to-antagonist balance check, using only the ratios that the literature
/// actually reports rather than invented ideals.
nonisolated struct BalanceRatio: Identifiable, Hashable, Sendable {
    var name: String
    var explanation: String
    var numeratorLabel: String
    var denominatorLabel: String
    var numeratorSets: Double
    var denominatorSets: Double
    /// The reference band, from the cited source.
    var referenceRange: ClosedRange<Double>
    var source: String

    var id: String { name }

    var ratio: Double? {
        guard denominatorSets > 0 else { return nil }
        return numeratorSets / denominatorSets
    }

    /// Whether both sides have enough work for the ratio to mean anything. Comparing two
    /// sets against one set is arithmetic, not information.
    var hasEnoughData: Bool { numeratorSets + denominatorSets >= 6 }

    var isBalanced: Bool? {
        guard hasEnoughData, let ratio else { return nil }
        return referenceRange.contains(ratio)
    }

    /// Which side is light, when the ratio sits outside the band.
    var lighterSide: String? {
        guard hasEnoughData, let ratio, !referenceRange.contains(ratio) else { return nil }
        return ratio < referenceRange.lowerBound ? numeratorLabel : denominatorLabel
    }
}

// MARK: - Analysis

nonisolated enum StrengthAnalysis {

    /// Build per-exercise progress from a set of lifting sessions.
    static func exerciseProgress(from workouts: [UnifiedWorkout]) -> [ExerciseProgress] {
        var grouped: [String: (name: String, systems: [BodySystem], points: [ExerciseProgress.Point])] = [:]

        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            guard let strength = workout.strength else { continue }
            for exercise in strength.exercises {
                let key = exercise.trackingKey
                let point = ExerciseProgress.Point(
                    date: workout.start,
                    estimatedOneRepMaxKg: exercise.measurement.supportsOneRepMax
                        ? OneRepMax.best(in: exercise.sets) : nil,
                    topSetWeightKg: exercise.topSetWeightKg,
                    volumeLoadKg: exercise.volumeLoadKg,
                    workingSets: exercise.workingSetCount,
                    totalReps: exercise.totalReps,
                    averageRPE: Stats.mean(exercise.workingSets.compactMap(\.rpe))
                )
                var entry = grouped[key] ?? (exercise.name, exercise.systems, [])
                // Prefer the most recent name and attribution.
                entry.name = exercise.name
                if !exercise.systems.isEmpty { entry.systems = exercise.systems }
                entry.points.append(point)
                grouped[key] = entry
            }
        }

        return grouped.map { key, entry in
            ExerciseProgress(
                trackingKey: key,
                name: entry.name,
                sessions: entry.points.sorted { $0.date < $1.date },
                systems: entry.systems
            )
        }
        .sorted { $0.sessionCount > $1.sessionCount }
    }

    /// Weekly hard sets per body system over a trailing window.
    static func muscleVolume(
        workouts: [UnifiedWorkout],
        windowDays: Int = 28,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MuscleVolume] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else {
            return []
        }
        let relevant = workouts.filter { $0.strength != nil && $0.day >= windowStart }
        let weeks = Double(windowDays) / 7

        var totals: [BodySystem: Double] = [:]
        var days: [BodySystem: Set<Date>] = [:]
        var last: [BodySystem: Date] = [:]
        // Per-week series, for the trend.
        var perWeek: [BodySystem: [Int: Double]] = [:]

        for workout in relevant {
            guard let strength = workout.strength else { continue }
            let credited = strength.setsPerSystem()
            let weekIndex = (calendar.dateComponents([.day], from: windowStart, to: workout.day).day ?? 0) / 7
            for (system, sets) in credited where sets > 0 {
                totals[system, default: 0] += sets
                days[system, default: []].insert(workout.day)
                if let existing = last[system] {
                    if workout.day > existing { last[system] = workout.day }
                } else {
                    last[system] = workout.day
                }
                perWeek[system, default: [:]][weekIndex, default: 0] += sets
            }
        }

        return BodySystem.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { system in
                let total = totals[system] ?? 0
                // Weekly series, zero-filled so a skipped week counts as zero rather than
                // being dropped and flattering the trend.
                let weekCount = Int(ceil(weeks))
                let series = (0..<weekCount).map { perWeek[system]?[$0] ?? 0 }
                let trend = series.count >= 3 ? Stats.theilSenTrend(series)?.slope : nil

                return MuscleVolume(
                    system: system,
                    setsPerWeek: weeks > 0 ? total / weeks : 0,
                    totalSets: total,
                    sessionCount: days[system]?.count ?? 0,
                    lastTrained: last[system],
                    weeklyTrend: trend
                )
            }
    }

    /// Balance checks, using only ratios with a citable reference band.
    static func balanceRatios(_ volumes: [MuscleVolume]) -> [BalanceRatio] {
        func sets(_ system: BodySystem) -> Double {
            volumes.first { $0.system == system }?.totalSets ?? 0
        }

        return [
            BalanceRatio(
                name: "Push and pull",
                explanation: "Chest and shoulder pressing against back pulling. Rough parity is the usual programming convention.",
                numeratorLabel: "Pulling",
                denominatorLabel: "Pressing",
                numeratorSets: sets(.back),
                denominatorSets: sets(.chest) + sets(.shoulders),
                // Convention rather than a measured ideal, so the band is generous.
                referenceRange: 0.7...1.4,
                source: "Common programming convention, not a measured ideal"
            ),
            BalanceRatio(
                name: "Hamstrings and quadriceps",
                explanation: "The hamstring to quadriceps ratio is the most studied balance measure in the knee-injury literature, where strength ratios near 0.6 and above are the usual reference.",
                numeratorLabel: "Hamstrings",
                denominatorLabel: "Quads",
                numeratorSets: setsFor(volumes, muscles: [.hamstrings, .glutes]),
                denominatorSets: setsFor(volumes, muscles: [.quads]),
                referenceRange: 0.5...1.5,
                source: "Hamstring to quadriceps strength ratio, knee-injury literature"
            ),
            BalanceRatio(
                name: "Lower body and upper body",
                explanation: "How the week splits between legs and everything above the waist.",
                numeratorLabel: "Legs",
                denominatorLabel: "Upper body",
                numeratorSets: sets(.legs),
                denominatorSets: sets(.chest) + sets(.back) + sets(.shoulders) + sets(.arms),
                referenceRange: 0.4...1.2,
                source: "Common programming convention"
            ),
        ]
    }

    /// Set totals for specific muscles, when the source attributed them precisely. Falls
    /// back to the region when it did not.
    private static func setsFor(_ volumes: [MuscleVolume], muscles: [MuscleGroup]) -> Double {
        // The volume roll-up is by system, so a muscle-level question is answered at the
        // system level. Documented rather than silently approximated.
        let systems = Set(muscles.map(\.system))
        return volumes.filter { systems.contains($0.system) }.reduce(0) { $0 + $1.totalSets }
    }

    // MARK: - Plateau and progress

    /// Whether a lift has genuinely stalled.
    nonisolated struct PlateauCheck: Hashable, Sendable {
        var exerciseName: String
        var trackingKey: String
        var sessionsConsidered: Int
        /// Robust slope in kilograms per session.
        var slopePerSession: Double
        var test: Stats.TrendTest
        /// Estimated one-rep max at the start and end of the window.
        var startValue: Double
        var endValue: Double

        /// A plateau is claimed only when a trend test finds NO significant direction over a
        /// decent number of sessions. That is the honest statement: not "you have stopped
        /// progressing", but "there is no detectable trend here".
        var isPlateau: Bool {
            test.direction == .none && sessionsConsidered >= 8
        }

        var isProgressing: Bool { test.direction == .increasing }
        var isRegressing: Bool { test.direction == .decreasing }

        var changeKg: Double { endValue - startValue }
        var changePercent: Double? {
            guard startValue > 0 else { return nil }
            return (endValue - startValue) / startValue * 100
        }
    }

    /// Check the movements with enough history to say anything about.
    static func plateauChecks(
        _ progress: [ExerciseProgress],
        minimumSessions: Int = 8,
        windowSessions: Int = 16
    ) -> [PlateauCheck] {
        progress.compactMap { exercise -> PlateauCheck? in
            let values = exercise.sessions.compactMap(\.estimatedOneRepMaxKg)
            guard values.count >= minimumSessions else { return nil }
            let window = Array(values.suffix(windowSessions))
            guard let test = Stats.mannKendall(window),
                  let first = window.first, let last = window.last else { return nil }
            let slope = Stats.theilSenTrend(window)?.slope ?? 0
            return PlateauCheck(
                exerciseName: exercise.name,
                trackingKey: exercise.trackingKey,
                sessionsConsidered: window.count,
                slopePerSession: slope,
                test: test,
                startValue: first,
                endValue: last
            )
        }
    }

    // MARK: - Personal records

    nonisolated struct StrengthRecord: Identifiable, Hashable, Sendable {
        var exerciseName: String
        var trackingKey: String
        var kind: Kind
        var valueKg: Double
        var reps: Int?
        var date: Date
        /// The previous best this beat, when there was one.
        var previousValueKg: Double?

        enum Kind: String, Sendable {
            case estimatedOneRepMax
            case heaviestSet
            case bestVolume

            var label: String {
                switch self {
                case .estimatedOneRepMax: "estimated max"
                case .heaviestSet:        "heaviest set"
                case .bestVolume:         "most volume"
                }
            }
        }

        var id: String { "\(trackingKey)-\(kind.rawValue)-\(date.timeIntervalSince1970)" }

        var improvementKg: Double? {
            guard let previousValueKg else { return nil }
            return valueKg - previousValueKg
        }
    }

    /// Records set within a recent window, so the app can note a real milestone without
    /// dredging up a two-year-old best.
    static func recentRecords(
        _ progress: [ExerciseProgress],
        withinDays: Int = 30,
        now: Date = Date()
    ) -> [StrengthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -withinDays, to: now) else {
            return []
        }
        var records: [StrengthRecord] = []

        for exercise in progress {
            // A record needs history to beat: a first-ever session is not a record.
            guard exercise.sessions.count >= 3 else { continue }

            func scan(_ kind: StrengthRecord.Kind, value: (ExerciseProgress.Point) -> Double?) {
                var best: Double = 0
                var previousBest: Double = 0
                for point in exercise.sessions {
                    guard let current = value(point), current > 0 else { continue }
                    if current > best {
                        previousBest = best
                        best = current
                        if point.date >= cutoff, previousBest > 0 {
                            records.append(StrengthRecord(
                                exerciseName: exercise.name,
                                trackingKey: exercise.trackingKey,
                                kind: kind,
                                valueKg: current,
                                reps: kind == .heaviestSet ? point.totalReps : nil,
                                date: point.date,
                                previousValueKg: previousBest
                            ))
                        }
                    }
                }
            }

            scan(.estimatedOneRepMax) { $0.estimatedOneRepMaxKg }
            scan(.heaviestSet) { $0.topSetWeightKg }
        }

        // Keep only the latest record per exercise and kind, newest first.
        var seen = Set<String>()
        return records
            .sorted { $0.date > $1.date }
            .filter { seen.insert("\($0.trackingKey)-\($0.kind.rawValue)").inserted }
    }

    // MARK: - Frequency

    /// How often each region is trained per week, which the hypertrophy literature
    /// associates with better outcomes when volume is split across more sessions.
    static func trainingFrequency(
        workouts: [UnifiedWorkout],
        windowDays: Int = 28,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BodySystem: Double] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else {
            return [:]
        }
        let weeks = Double(windowDays) / 7
        var days: [BodySystem: Set<Date>] = [:]
        for workout in workouts where workout.strength != nil && workout.day >= windowStart {
            for system in workout.strength?.systemsWorked ?? [] {
                days[system, default: []].insert(workout.day)
            }
        }
        return days.mapValues { Double($0.count) / weeks }
    }
}
