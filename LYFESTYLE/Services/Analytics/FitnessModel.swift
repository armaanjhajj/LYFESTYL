//
//  FitnessModel.swift
//  LYFESTYL
//
//  The impulse-response view of training: how much fitness has accumulated, how much
//  fatigue is sitting on top of it, and whether the ramp is sustainable.
//
//  Built on Banister's two-component model, which is the basis of every "fitness and
//  freshness" chart in the sport. Two exponentially weighted averages of daily load,
//  one slow (fitness) and one fast (fatigue), and their difference (form).
//
//  A note on honesty, because this area of sports science is genuinely contested:
//  the acute-to-chronic workload ratio is included here because it is useful for
//  spotting a spike, but its famous "sweet spot" has been seriously criticised
//  (Impellizzeri and colleagues showed the classic construction suffers from
//  mathematical coupling and spurious-correlation artifacts). So this file computes
//  the EWMA variant, reports an UNCOUPLED ratio alongside it, and the insight layer
//  frames a high ratio as "this is a sharp increase" rather than as an injury-risk
//  prediction. The app describes what changed; it does not claim to forecast injury.
//

import Foundation

// MARK: - One day of the model

/// The model's state on a single day.
struct FitnessPoint: Identifiable, Hashable, Sendable {
    var date: Date
    /// Total training load recorded on this day, in TSS-equivalent points.
    var load: Double
    /// Chronic training load: the slow 42-day exponentially weighted average, read as
    /// accumulated fitness.
    var fitness: Double
    /// Acute training load: the fast 7-day exponentially weighted average, read as
    /// accumulated fatigue.
    var fatigue: Double
    /// Form, or training stress balance: yesterday's fitness minus yesterday's
    /// fatigue. Using YESTERDAY's values is the standard convention, because it
    /// answers "how fresh did I wake up today" rather than being retroactively
    /// changed by today's own session.
    var form: Double

    var id: Date { date }

    /// Whether anything was actually trained on this day.
    var isTrainingDay: Bool { load > 0 }
}

// MARK: - Interpretation bands

/// How to read a form value. These bands are the widely used practitioner
/// conventions, and the app presents them as description rather than prescription.
enum FormState: String, Hashable, Sendable, CaseIterable {
    /// Well above baseline freshness. Race-ready, but fitness is decaying.
    case fresh
    /// Slightly positive. Recovered and ready.
    case ready
    /// Mildly negative. The productive zone for building.
    case building
    /// Strongly negative. Sustainable only briefly.
    case strained
    /// Very strongly negative. Sustained here, this is where things break.
    case overreached

    /// Practitioner bands on training stress balance.
    static func classify(form: Double) -> FormState {
        switch form {
        case 15...:       .fresh
        case 5..<15:      .ready
        case -10..<5:     .building
        case -30..<(-10): .strained
        default:          .overreached
        }
    }

    var label: String {
        switch self {
        case .fresh:      "FRESH"
        case .ready:      "READY"
        case .building:   "BUILDING"
        case .strained:   "STRAINED"
        case .overreached:"DEEP FATIGUE"
        }
    }

    /// Neutral description. Never a verdict on the person.
    var describing: String {
        switch self {
        case .fresh:
            "Your recent load is well below what you have built. This is what a taper looks like."
        case .ready:
            "Recent load is a little below your accumulated fitness. Rested."
        case .building:
            "Recent load is slightly above your accumulated fitness. This is the usual range for building."
        case .strained:
            "Recent load is well above your accumulated fitness. Sustainable for a block, not indefinitely."
        case .overreached:
            "Recent load is far above your accumulated fitness. This is a heavy place to sit for long."
        }
    }
}

// MARK: - Load ramp

/// The acute-to-chronic load relationship, with the caveats it deserves.
struct LoadRamp: Hashable, Sendable {
    /// Exponentially weighted acute load (7-day span).
    var acute: Double
    /// Exponentially weighted chronic load (28-day span).
    var chronic: Double
    /// The ratio, exponentially weighted (Williams et al. 2017).
    var ratio: Double?
    /// The same ratio with the acute window REMOVED from the chronic baseline, which
    /// eliminates the mathematical coupling that inflates the standard construction.
    var uncoupledRatio: Double?
    /// Week-over-week change in chronic load, in points per week. The clearest single
    /// number for "am I ramping too fast".
    var weeklyFitnessChange: Double?
    /// Days of data behind these figures. Below about 28 the chronic term has not
    /// converged and the ratio should not be shown at all.
    var daysOfData: Int

    /// Whether there is enough history for the chronic term to mean anything.
    var isEstablished: Bool { daysOfData >= 28 }

    enum Band: String, Hashable, Sendable {
        /// Materially less load than the recent baseline. Detraining or resting.
        case detraining
        /// Load in line with the baseline.
        case steady
        /// A moderate increase.
        case increasing
        /// A sharp increase relative to the baseline.
        case spike

        var label: String {
            switch self {
            case .detraining: "EASING OFF"
            case .steady:     "STEADY"
            case .increasing: "BUILDING"
            case .spike:      "SHARP INCREASE"
            }
        }
    }

    /// Band the ratio. Boundaries follow the commonly cited 0.8 and 1.3 marks, but
    /// note the naming: this describes the SHAPE OF THE CHANGE, not a risk level.
    var band: Band? {
        guard isEstablished, let ratio else { return nil }
        switch ratio {
        case ..<0.8:   return .detraining
        case 0.8..<1.3: return ratio < 1.05 ? .steady : .increasing
        default:       return .spike
        }
    }
}

// MARK: - Weekly rollup

struct TrainingWeek: Identifiable, Hashable, Sendable {
    /// First day of the week (respecting the user's calendar).
    var weekStart: Date
    var totalLoad: Double
    var sessionCount: Int
    var totalSeconds: Double
    var totalDistanceMeters: Double
    /// Days in the week with no session at all.
    var restDays: Int
    /// Foster's training monotony: mean daily load divided by its standard deviation.
    /// High monotony means every day looked the same, which the literature associates
    /// with worse adaptation than the same total load varied properly.
    var monotony: Double?
    /// Foster's training strain: weekly load times monotony.
    var strain: Double?
    /// Fraction of heart-rate time spent in zones 1 and 2.
    var easyFraction: Double?
    /// Fraction in zones 4 and 5.
    var hardFraction: Double?

    var id: Date { weekStart }

    var averageDailyLoad: Double { totalLoad / 7 }
}

// MARK: - The model

enum FitnessModel {

    /// Time constant for chronic load (fitness), in days. 42 days is Banister's
    /// original and the universal convention.
    static let fitnessTimeConstant = 42.0
    /// Time constant for acute load (fatigue), in days.
    static let fatigueTimeConstant = 7.0

    /// The exponential decay factor for a time constant, `1 - e^(-1/tau)`.
    ///
    /// This is the mathematically correct impulse-response form. The commonly quoted
    /// `1/42` is a first-order approximation of it: 1 - e^(-1/42) = 0.023565 against
    /// 1/42 = 0.023810, a difference of about one percent. The exact form is used here
    /// because it is what the underlying model actually specifies and it costs nothing.
    static func decayFactor(timeConstant tau: Double) -> Double {
        guard tau > 0 else { return 1 }
        return 1 - exp(-1 / tau)
    }

    /// Run the two-component model over a contiguous daily load series.
    ///
    /// `dailyLoads` MUST be one entry per consecutive calendar day, with 0 for rest
    /// days. A rest day is a real zero here (genuinely no training load), which is
    /// different from an unmeasured metric, so zero-filling is correct rather than
    /// dishonest. The caller is responsible for building the contiguous run.
    static func run(dailyLoads: [(date: Date, load: Double)]) -> [FitnessPoint] {
        guard !dailyLoads.isEmpty else { return [] }

        let fitnessDecay = decayFactor(timeConstant: fitnessTimeConstant)
        let fatigueDecay = decayFactor(timeConstant: fatigueTimeConstant)

        var points: [FitnessPoint] = []
        points.reserveCapacity(dailyLoads.count)

        // Seed both averages at zero. The first six weeks are therefore a warm-up
        // during which fitness is understated; `LoadRamp.isEstablished` is what stops
        // the UI from over-reading that period.
        var fitness = 0.0
        var fatigue = 0.0

        for entry in dailyLoads {
            // Form uses YESTERDAY's state, before today's session is folded in.
            let form = fitness - fatigue
            fitness += (entry.load - fitness) * fitnessDecay
            fatigue += (entry.load - fatigue) * fatigueDecay
            points.append(FitnessPoint(
                date: entry.date,
                load: entry.load,
                fitness: fitness,
                fatigue: fatigue,
                form: form
            ))
        }
        return points
    }

    /// The load ramp as of the end of a daily load series.
    static func loadRamp(dailyLoads: [(date: Date, load: Double)]) -> LoadRamp {
        let loads = dailyLoads.map(\.load)
        let n = loads.count

        // Exponentially weighted acute and chronic loads, per Williams et al. (2017),
        // "Better way to determine the acute:chronic workload ratio?", Br J Sports Med
        // 51:209-210. Uses lambda = 2 / (N + 1).
        let acuteAlpha = Stats.ewmaAlpha(spanDays: 7)
        let chronicAlpha = Stats.ewmaAlpha(spanDays: 28)
        let acuteSeries = Stats.ewma(loads, alpha: acuteAlpha)
        let chronicSeries = Stats.ewma(loads, alpha: chronicAlpha)

        let acute = acuteSeries.last ?? 0
        let chronic = chronicSeries.last ?? 0
        let ratio: Double? = chronic > 1 ? acute / chronic : nil

        // The uncoupled ratio: compare the last 7 days against the 21 days BEFORE
        // them, so the acute window is not part of its own denominator. Without this,
        // the ratio is correlated with itself by construction, which is the core of
        // the methodological criticism of ACWR.
        var uncoupled: Double?
        if n >= 28 {
            let recent = Array(loads.suffix(7))
            let earlier = Array(loads.suffix(28).prefix(21))
            if let recentMean = Stats.mean(recent), let earlierMean = Stats.mean(earlier),
               earlierMean > 1 {
                uncoupled = recentMean / earlierMean
            }
        }

        // Week-over-week change in chronic load.
        var weeklyChange: Double?
        if chronicSeries.count > 7 {
            let today = chronicSeries[chronicSeries.count - 1]
            let weekAgo = chronicSeries[chronicSeries.count - 8]
            weeklyChange = today - weekAgo
        }

        return LoadRamp(
            acute: acute,
            chronic: chronic,
            ratio: ratio,
            uncoupledRatio: uncoupled,
            weeklyFitnessChange: weeklyChange,
            daysOfData: n
        )
    }

    // MARK: - Monotony and strain

    /// Foster's training monotony over a set of daily loads: mean divided by standard
    /// deviation.
    ///
    /// Foster (1998), "Monitoring training in athletes with reference to overtraining
    /// syndrome", Med Sci Sports Exerc 30:1164-1168. Foster's observation was that
    /// athletes broke down when load was high AND unvarying; monotony above roughly 2
    /// is the commonly cited concern point.
    ///
    /// Zero-load rest days are included on purpose: taking a day off is precisely what
    /// lowers monotony, so excluding rest days would invert the meaning.
    static func monotony(dailyLoads: [Double]) -> Double? {
        guard dailyLoads.count >= 5,
              let mean = Stats.mean(dailyLoads), mean > 0,
              let sd = Stats.standardDeviation(dailyLoads), sd > 0
        else { return nil }
        return mean / sd
    }

    /// Foster's training strain: total weekly load times monotony.
    static func strain(dailyLoads: [Double]) -> Double? {
        guard let monotony = monotony(dailyLoads: dailyLoads) else { return nil }
        return dailyLoads.reduce(0, +) * monotony
    }

    /// The monotony level above which Foster's work suggests variation is worth adding.
    static let monotonyConcernThreshold = 2.0

    // MARK: - Weekly aggregation

    /// Group scored sessions into calendar weeks.
    static func weeks(
        workouts: [UnifiedWorkout],
        loads: [String: TrainingLoadResult],
        zones: [String: ZoneDistribution],
        calendar: Calendar = .current
    ) -> [TrainingWeek] {
        guard !workouts.isEmpty else { return [] }

        var byWeek: [Date: [UnifiedWorkout]] = [:]
        for workout in workouts {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: workout.start)?.start
            else { continue }
            byWeek[weekStart, default: []].append(workout)
        }

        return byWeek.map { weekStart, sessions in
            // Daily loads across the seven days, zero-filled, so monotony is right.
            var perDay = [Double](repeating: 0, count: 7)
            var trainedDays = Set<Int>()
            for session in sessions {
                let offset = calendar.dateComponents([.day], from: weekStart, to: session.day).day ?? 0
                guard offset >= 0, offset < 7 else { continue }
                perDay[offset] += loads[session.id]?.load ?? 0
                trainedDays.insert(offset)
            }

            var easySeconds = 0.0
            var hardSeconds = 0.0
            var zonedSeconds = 0.0
            for session in sessions {
                guard let distribution = zones[session.id] else { continue }
                easySeconds += distribution.easySeconds
                hardSeconds += distribution.hardSeconds
                zonedSeconds += distribution.total
            }

            return TrainingWeek(
                weekStart: weekStart,
                totalLoad: perDay.reduce(0, +),
                sessionCount: sessions.count,
                totalSeconds: sessions.reduce(0) { $0 + $1.movingSeconds },
                totalDistanceMeters: sessions.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
                restDays: 7 - trainedDays.count,
                monotony: monotony(dailyLoads: perDay),
                strain: strain(dailyLoads: perDay),
                easyFraction: zonedSeconds > 0 ? easySeconds / zonedSeconds : nil,
                hardFraction: zonedSeconds > 0 ? hardSeconds / zonedSeconds : nil
            )
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Intensity distribution

    /// How polarized the training is: the share of time spent easy versus hard.
    ///
    /// The polarized-training literature (Seiler and colleagues) consistently finds
    /// that well-trained endurance athletes spend roughly 75 to 80 percent of their
    /// time at low intensity. This reports the actual split and leaves the
    /// interpretation to the insight layer, which frames it as a comparison to that
    /// published pattern rather than as a rule.
    struct IntensityDistribution: Hashable, Sendable {
        var easyFraction: Double
        var moderateFraction: Double
        var hardFraction: Double
        var totalSeconds: Double

        /// The share at low intensity that the polarized literature describes.
        static let publishedEasyTarget = 0.80

        /// How far the actual easy share sits from that pattern, in percentage points.
        var easyGapFromPublishedTarget: Double {
            (easyFraction - Self.publishedEasyTarget) * 100
        }

        /// Enough zoned time to be worth describing (about five hours).
        var hasEnoughData: Bool { totalSeconds >= 18000 }
    }

    static func intensityDistribution(_ distributions: [ZoneDistribution]) -> IntensityDistribution? {
        var easy = 0.0, moderate = 0.0, hard = 0.0
        for distribution in distributions {
            easy += distribution.seconds[0] + distribution.seconds[1]
            moderate += distribution.seconds[2]
            hard += distribution.seconds[3] + distribution.seconds[4]
        }
        let total = easy + moderate + hard
        guard total > 0 else { return nil }
        return IntensityDistribution(
            easyFraction: easy / total,
            moderateFraction: moderate / total,
            hardFraction: hard / total,
            totalSeconds: total
        )
    }

    // MARK: - Consistency

    struct Consistency: Hashable, Sendable {
        /// Consecutive days with at least one session, counting back from the most
        /// recent training day.
        var currentStreak: Int
        var longestStreak: Int
        /// Days since the most recent day with no session at all.
        var daysSinceRest: Int
        /// Sessions per week over the window.
        var sessionsPerWeek: Double
        /// Fraction of days in the window with a session.
        var activeDayFraction: Double
    }

    /// Consistency over a contiguous daily load series.
    static func consistency(dailyLoads: [(date: Date, load: Double)]) -> Consistency? {
        guard !dailyLoads.isEmpty else { return nil }
        let active = dailyLoads.map { $0.load > 0 }

        var longest = 0
        var running = 0
        for day in active {
            running = day ? running + 1 : 0
            longest = max(longest, running)
        }

        // Current streak counts back from the end.
        var current = 0
        for day in active.reversed() {
            if day { current += 1 } else { break }
        }

        // Days since the last rest day.
        var sinceRest = 0
        for day in active.reversed() {
            if day { sinceRest += 1 } else { break }
        }

        let activeCount = active.filter { $0 }.count
        let weeks = Double(dailyLoads.count) / 7

        return Consistency(
            currentStreak: current,
            longestStreak: longest,
            daysSinceRest: sinceRest,
            sessionsPerWeek: weeks > 0 ? Double(activeCount) / weeks : 0,
            activeDayFraction: Double(activeCount) / Double(dailyLoads.count)
        )
    }

    // MARK: - Building the contiguous series

    /// Build a gap-free daily load series from scored sessions.
    ///
    /// Rest days become explicit zeros, which is what the exponential model needs.
    /// The series runs from the first session (or `from`, whichever is later) to
    /// `through`.
    static func dailyLoadSeries(
        workouts: [UnifiedWorkout],
        loads: [String: TrainingLoadResult],
        from: Date? = nil,
        through: Date = Date(),
        calendar: Calendar = .current
    ) -> [(date: Date, load: Double)] {
        guard !workouts.isEmpty else { return [] }

        var totals: [Date: Double] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.start)
            totals[day, default: 0] += loads[workout.id]?.load ?? 0
        }

        let earliest = totals.keys.min() ?? calendar.startOfDay(for: through)
        let start = from.map { max(calendar.startOfDay(for: $0), earliest) } ?? earliest
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }

        var series: [(date: Date, load: Double)] = []
        var cursor = start
        while cursor <= end {
            series.append((date: cursor, load: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return series
    }
}
