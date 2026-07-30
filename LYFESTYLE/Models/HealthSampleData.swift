//
//  HealthSampleData.swift
//  LYFESTYL
//
//  A synthetic training history for previews and for verifying the analysis end to end.
//
//  DEBUG ONLY. This never ships in a release build, and it is never mixed with real data:
//  it is only loaded when the app is launched with LYFE_PREVIEW=1, the same switch the rest
//  of the app already uses.
//
//  The generator is deliberately REALISTIC rather than random, because its real job is to
//  exercise the analysis. It produces a periodised block with build and recovery weeks, an
//  upward drift in fitness, a genuine relationship between sleep and next-day heart-rate
//  variability, a resting-heart-rate step partway through, a plateauing bench press against a
//  climbing squat, and gaps where a sensor was not worn. If the analysis cannot find those
//  things, it is not working.
//
//  Everything is generated from a fixed seed, so a run is reproducible and a change in output
//  means a change in the code rather than in the dice.
//

#if DEBUG
import Foundation

nonisolated enum HealthSampleData {

    /// A small deterministic generator. Not cryptographic, just repeatable.
    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let bits = (state >> 11) & 0x1F_FFFF_FFFF_FFFF
            return Double(bits) / Double(0x1F_FFFF_FFFF_FFFF)
        }

        /// Uniform in a range.
        mutating func inRange(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }

        /// Approximately normal, by summing uniforms (the central limit theorem at n = 6).
        mutating func normal(mean: Double, sd: Double) -> Double {
            var total = 0.0
            for _ in 0..<6 { total += next() }
            return mean + (total - 3) / 0.7071 * sd * 0.4082
        }

        mutating func chance(_ probability: Double) -> Bool { next() < probability }
    }

    /// How many days of history to generate.
    static let days = 180

    /// Build the whole sample set.
    static func generate(now: Date = Date(), calendar: Calendar = .current)
        -> (workouts: [UnifiedWorkout], snapshots: [DailySnapshot]) {
        var random = Random(seed: 20260730)
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else {
            return ([], [])
        }

        var workouts: [UnifiedWorkout] = []
        var snapshots: [DailySnapshot] = []

        // Sleep is generated first, because next-day HRV is derived from it. That is what
        // creates a real, discoverable relationship for the correlation engine to find.
        var sleepHours: [Double] = []
        for day in 0..<days {
            let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: day, to: start)!)
            // Later nights on Friday and Saturday, which also gives the regularity index
            // something real to measure.
            let isWeekend = weekday == 6 || weekday == 7
            let base = isWeekend ? 7.9 : 7.1
            sleepHours.append(max(4.2, min(9.8, random.normal(mean: base, sd: 0.85))))
        }

        // Fitness rises across the block, which shows up in pace at a given heart rate.
        for day in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            let weekIndex = day / 7
            // Three build weeks then a recovery week, the classic block structure.
            let isRecoveryWeek = weekIndex % 4 == 3
            let progress = Double(day) / Double(days)
            let fitnessGain = 1 + progress * 0.10   // ten percent faster by the end

            let weekday = calendar.component(.weekday, from: date)
            // Rest on Mondays, plus an extra rest day in recovery weeks.
            let restDay = weekday == 2 || (isRecoveryWeek && weekday == 5)

            if !restDay {
                let sessions = sessionsFor(
                    weekday: weekday,
                    date: date,
                    fitnessGain: fitnessGain,
                    isRecoveryWeek: isRecoveryWeek,
                    dayIndex: day,
                    random: &random
                )
                workouts.append(contentsOf: sessions)
            }

            snapshots.append(snapshot(
                date: date,
                dayIndex: day,
                sleepHours: sleepHours[day],
                previousSleep: day > 0 ? sleepHours[day - 1] : sleepHours[day],
                isRecoveryWeek: isRecoveryWeek,
                random: &random,
                calendar: calendar
            ))
        }

        return (workouts.sorted { $0.start > $1.start }, snapshots)
    }

    // MARK: - Sessions

    private static func sessionsFor(
        weekday: Int,
        date: Date,
        fitnessGain: Double,
        isRecoveryWeek: Bool,
        dayIndex: Int,
        random: inout Random
    ) -> [UnifiedWorkout] {
        var result: [UnifiedWorkout] = []
        let calendar = Calendar.current
        let intensityScale = isRecoveryWeek ? 0.72 : 1.0

        switch weekday {
        case 3, 6:   // Tuesday and Friday: lifting
            let isUpper = weekday == 3
            result.append(strengthSession(
                date: calendar.date(bySettingHour: 18, minute: 15, second: 0, of: date) ?? date,
                isUpper: isUpper,
                dayIndex: dayIndex,
                intensityScale: intensityScale,
                random: &random
            ))
        case 4:      // Wednesday: intervals
            result.append(runSession(
                date: calendar.date(bySettingHour: 6, minute: 40, second: 0, of: date) ?? date,
                kilometers: random.inRange(8...11),
                targetHeartRate: 168 * intensityScale,
                fitnessGain: fitnessGain,
                sport: .run,
                hilly: false,
                random: &random
            ))
        case 5:      // Thursday: ride
            result.append(rideSession(
                date: calendar.date(bySettingHour: 17, minute: 30, second: 0, of: date) ?? date,
                minutes: random.inRange(55...95) * intensityScale,
                fitnessGain: fitnessGain,
                random: &random
            ))
        case 7:      // Saturday: long run
            result.append(runSession(
                date: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date,
                kilometers: random.inRange(16...24) * intensityScale,
                targetHeartRate: 146,
                fitnessGain: fitnessGain,
                sport: .trailRun,
                hilly: true,
                random: &random
            ))
        case 1:      // Sunday: easy run
            result.append(runSession(
                date: calendar.date(bySettingHour: 9, minute: 20, second: 0, of: date) ?? date,
                kilometers: random.inRange(6...9),
                targetHeartRate: 138,
                fitnessGain: fitnessGain,
                sport: .run,
                hilly: false,
                random: &random
            ))
        default:
            break
        }
        return result
    }

    /// A run, with a full sample series so decoupling and zones are computable.
    private static func runSession(
        date: Date,
        kilometers: Double,
        targetHeartRate: Double,
        fitnessGain: Double,
        sport: WorkoutSport,
        hilly: Bool,
        random: inout Random
    ) -> UnifiedWorkout {
        // Faster over time at the same heart rate, which is the signal the efficiency-factor
        // trend is supposed to detect.
        let basePace = 315.0 / fitnessGain          // seconds per kilometer
        let pace = basePace * random.inRange(0.96...1.05)
        let seconds = pace * kilometers
        let distance = kilometers * 1000

        let sampleCount = max(20, Int(seconds / 20))
        var hrOffsets: [Double] = [], hrValues: [Double] = []
        var spOffsets: [Double] = [], spValues: [Double] = []
        var altOffsets: [Double] = [], altValues: [Double] = []
        var distOffsets: [Double] = [], distValues: [Double] = []

        let meanSpeed = distance / seconds
        var cumulative = 0.0
        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleCount - 1)
            let offset = t * seconds

            // Heart rate lags at the start and drifts up over a long effort, which is exactly
            // what aerobic decoupling measures.
            let warmup = min(1, offset / 420)
            let drift = 1 + t * (hilly ? 0.06 : 0.03)
            let hr = targetHeartRate * warmup * drift + random.normal(mean: 0, sd: 2.5)

            let speed = meanSpeed * (1 - t * 0.03) + random.normal(mean: 0, sd: 0.12)
            cumulative += max(0, speed) * (seconds / Double(sampleCount))

            hrOffsets.append(offset); hrValues.append(max(70, hr))
            spOffsets.append(offset); spValues.append(max(0.5, speed))
            distOffsets.append(offset); distValues.append(cumulative)
            if hilly {
                altOffsets.append(offset)
                altValues.append(120 + sin(t * .pi * 3) * 45 + random.normal(mean: 0, sd: 3))
            }
        }

        let origin = SourceRef(
            source: .garmin,
            foreignID: "sample-run-\(Int(date.timeIntervalSince1970))",
            updatedAt: date
        )
        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: sport,
            title: title(for: sport, date: date),
            start: date,
            end: date.addingTimeInterval(seconds),
            movingSeconds: seconds,
            isIndoor: false,
            distanceMeters: distance,
            activeEnergyKcal: kilometers * 68,
            elevationGainMeters: hilly ? random.inRange(180...420) : random.inRange(15...70),
            averageHeartRate: Stats.mean(hrValues),
            maxHeartRate: hrValues.max(),
            averageSpeedMps: meanSpeed,
            maxSpeedMps: spValues.max(),
            averageCadence: random.inRange(168...178),
            heartRateSeries: MetricSeries(offsets: hrOffsets, values: hrValues),
            speedSeries: MetricSeries(offsets: spOffsets, values: spValues),
            altitudeSeries: hilly ? MetricSeries(offsets: altOffsets, values: altValues) : nil,
            distanceSeries: MetricSeries(offsets: distOffsets, values: distValues)
        )
    }

    private static func rideSession(
        date: Date,
        minutes: Double,
        fitnessGain: Double,
        random: inout Random
    ) -> UnifiedWorkout {
        let seconds = minutes * 60
        let averagePower = 195 * fitnessGain * random.inRange(0.94...1.08)
        let sampleCount = max(20, Int(seconds / 20))

        var hrOffsets: [Double] = [], hrValues: [Double] = []
        var pwOffsets: [Double] = [], pwValues: [Double] = []
        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleCount - 1)
            let offset = t * seconds
            // Surges, so normalized power sits meaningfully above the average.
            let surge = random.chance(0.16) ? random.inRange(1.25...1.7) : 1.0
            let power = averagePower * surge + random.normal(mean: 0, sd: 22)
            let hr = 128 + (power / averagePower) * 26 + t * 5 + random.normal(mean: 0, sd: 3)
            pwOffsets.append(offset); pwValues.append(max(0, power))
            hrOffsets.append(offset); hrValues.append(max(70, hr))
        }

        let origin = SourceRef(
            source: .garmin,
            foreignID: "sample-ride-\(Int(date.timeIntervalSince1970))",
            updatedAt: date
        )
        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: .ride,
            title: title(for: .ride, date: date),
            start: date,
            end: date.addingTimeInterval(seconds),
            movingSeconds: seconds,
            isIndoor: false,
            distanceMeters: seconds * random.inRange(7.2...8.4),
            activeEnergyKcal: averagePower * seconds / 1000 * 0.95,
            elevationGainMeters: random.inRange(200...620),
            averageHeartRate: Stats.mean(hrValues),
            maxHeartRate: hrValues.max(),
            averagePowerWatts: Stats.mean(pwValues),
            maxPowerWatts: pwValues.max(),
            averageCadence: random.inRange(82...92),
            heartRateSeries: MetricSeries(offsets: hrOffsets, values: hrValues),
            powerSeries: MetricSeries(offsets: pwOffsets, values: pwValues)
        )
    }

    /// A Hevy-shaped lifting session. The bench press deliberately PLATEAUS while the squat
    /// climbs, so the plateau detector has both cases to distinguish.
    private static func strengthSession(
        date: Date,
        isUpper: Bool,
        dayIndex: Int,
        intensityScale: Double,
        random: inout Random
    ) -> UnifiedWorkout {
        let progress = Double(dayIndex) / Double(days)

        let plan: [(name: String, baseKg: Double, gainKg: Double, reps: [Int])]
        if isUpper {
            plan = [
                // Flat: no trend to find.
                ("Barbell Bench Press", 82.5, 0.0, [8, 8, 6]),
                ("Barbell Row", 70.0, 6.0, [10, 10, 8]),
                ("Overhead Press", 47.5, 3.5, [8, 8, 8]),
                ("Lat Pulldown", 63.0, 5.0, [12, 12, 10]),
                ("Dumbbell Curl", 16.0, 2.0, [12, 12]),
            ]
        } else {
            plan = [
                // Clear upward trend.
                ("Barbell Back Squat", 105.0, 18.0, [6, 6, 5]),
                ("Romanian Deadlift", 90.0, 12.0, [8, 8, 8]),
                ("Leg Press", 180.0, 30.0, [12, 12, 10]),
                ("Calf Raise", 60.0, 8.0, [15, 15]),
            ]
        }

        var exercises: [StrengthExercise] = []
        for (index, item) in plan.enumerated() {
            let load = (item.baseKg + item.gainKg * progress) * intensityScale
            let matched = ExerciseLibrary.shared.match(name: item.name)
            let sets = item.reps.enumerated().map { setIndex, reps in
                StrengthSet(
                    index: setIndex,
                    type: .normal,
                    // Round to the nearest 2.5 kg, the way real plates work.
                    weightKg: (load * random.inRange(0.98...1.02) / 2.5).rounded() * 2.5,
                    reps: reps,
                    rpe: min(10, random.normal(mean: 8, sd: 0.7))
                )
            }
            exercises.append(StrengthExercise(
                index: index,
                name: matched?.name ?? item.name,
                templateID: "sample-\(item.name.replacingOccurrences(of: " ", with: "-"))",
                libraryExerciseID: matched?.id,
                measurement: .weightReps,
                primaryTargets: (matched?.primary ?? []).map { MuscleTarget.muscle($0) },
                secondaryTargets: (matched?.secondary ?? []).map { MuscleTarget.muscle($0) },
                equipment: matched?.equipment ?? .barbell,
                sets: sets
            ))
        }

        let seconds = random.inRange(3300...4800)
        let origin = SourceRef(
            source: .hevy,
            foreignID: "sample-lift-\(Int(date.timeIntervalSince1970))",
            updatedAt: date
        )
        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: .strengthTraining,
            title: isUpper ? "Upper body" : "Lower body",
            start: date,
            end: date.addingTimeInterval(seconds),
            movingSeconds: seconds,
            isIndoor: true,
            strength: StrengthSession(exercises: exercises)
        )
    }

    // MARK: - Daily wellness

    private static func snapshot(
        date: Date,
        dayIndex: Int,
        sleepHours: Double,
        previousSleep: Double,
        isRecoveryWeek: Bool,
        random: inout Random,
        calendar: Calendar
    ) -> DailySnapshot {
        // A resting-heart-rate step two thirds of the way in, for the CUSUM detector.
        let shifted = dayIndex > Int(Double(days) * 0.66)
        let restingBase = shifted ? 52.0 : 48.0

        // HRV genuinely responds to the PREVIOUS night's sleep, so the correlation engine has
        // a real relationship to find at a lag of one day.
        let sleepEffect = (previousSleep - 7.2) * 4.5
        let hrv = max(18, random.normal(mean: 62 + sleepEffect, sd: 7))
        let resting = max(38, random.normal(mean: restingBase - sleepEffect * 0.15, sd: 2.2))

        // Some days the watch was not worn, so the analysis has to cope with gaps.
        let wornOvernight = !random.chance(0.06)

        let bedtimeHour = 22.0 + (sleepHours - 7.2) * -0.35 + random.normal(mean: 0, sd: 0.7)
        let bedtime = calendar.date(
            byAdding: .minute,
            value: Int((bedtimeHour - 24) * 60),
            to: calendar.startOfDay(for: date)
        ) ?? date
        let wake = bedtime.addingTimeInterval(sleepHours * 3600)

        // Stage split around the population reference proportions, with real variation.
        let deep = sleepHours * 3600 * random.inRange(0.13...0.21)
        let rem = sleepHours * 3600 * random.inRange(0.18...0.26)
        let core = sleepHours * 3600 - deep - rem

        let night = wornOvernight ? SleepNight(
            date: calendar.startOfDay(for: date),
            bedtime: bedtime,
            wakeTime: wake,
            inBedSeconds: sleepHours * 3600 + random.inRange(600...2400),
            asleepSeconds: sleepHours * 3600,
            awakeSeconds: random.inRange(300...1800),
            deepSeconds: deep,
            coreSeconds: core,
            remSeconds: rem,
            awakenings: Int(random.inRange(1...4)),
            source: .garmin
        ) : nil

        return DailySnapshot(
            date: calendar.startOfDay(for: date),
            sleep: night,
            restingHeartRate: wornOvernight ? resting : nil,
            heartRateVariabilityMs: wornOvernight ? hrv : nil,
            respiratoryRate: wornOvernight ? random.normal(mean: 14.2, sd: 0.8) : nil,
            oxygenSaturationPercent: wornOvernight ? random.normal(mean: 96.5, sd: 1.1) : nil,
            wristTemperatureDeltaC: wornOvernight ? random.normal(mean: 0, sd: 0.32) : nil,
            steps: random.normal(mean: 9800, sd: 2600),
            activeEnergyKcal: random.normal(mean: 720, sd: 260),
            exerciseMinutes: random.normal(mean: 58, sd: 26),
            standHours: random.inRange(9...14),
            flightsClimbed: random.inRange(4...22),
            timeInDaylightMinutes: random.normal(mean: 72, sd: 38),
            vo2Max: 51 + Double(dayIndex) / Double(days) * 2.4 + random.normal(mean: 0, sd: 0.4),
            bodyMassKg: 74.5 - Double(dayIndex) / Double(days) * 1.8 + random.normal(mean: 0, sd: 0.35),
            bodyFatPercent: random.normal(mean: 14.5, sd: 0.6),
            mindfulMinutes: random.chance(0.3) ? random.inRange(5...20) : nil,
            bodyBattery: wornOvernight ? random.normal(mean: 68 + sleepEffect * 0.8, sd: 12) : nil,
            stressAverage: wornOvernight ? random.normal(mean: 32 - sleepEffect * 0.4, sd: 9) : nil,
            garminHrvRmssdMs: wornOvernight ? hrv * random.inRange(0.85...1.1) : nil,
            contributingSources: [.garmin, .appleHealth]
        )
    }

    // MARK: - Helpers

    private static func title(for sport: WorkoutSport, date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let partOfDay: String
        switch hour {
        case 0..<12:  partOfDay = "Morning"
        case 12..<17: partOfDay = "Afternoon"
        default:      partOfDay = "Evening"
        }
        return "\(partOfDay) \(sport.label)"
    }
}
#endif
