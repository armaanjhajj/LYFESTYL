//
//  SampleData.swift
//  LYFESTYL
//
//  DEBUG-only seed data for previews and local UI verification. Activated by
//  launching with the environment variable LYFE_PREVIEW=1 (see AuthManager /
//  JournalStore). Never compiled into release builds.
//

#if DEBUG
import Foundation

enum SampleData {
    static let isPreview = ProcessInfo.processInfo.environment["LYFE_PREVIEW"] == "1"
    static let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    /// Measured HealthKit values for previews (so STYL shows the measured lane).
    static let healthSummary = HealthSummary(
        metrics: [
            MeasuredMetric(kind: .steps, value: 8243, asOf: Date()),
            MeasuredMetric(kind: .activeEnergy, value: 540, asOf: Date()),
            MeasuredMetric(kind: .exerciseMinutes, value: 38, asOf: Date()),
            MeasuredMetric(kind: .walkingRunningDistance, value: 3.4, asOf: Date()),
            MeasuredMetric(kind: .restingHeartRate, value: 58, asOf: Date()),
            MeasuredMetric(kind: .heartRateVariability, value: 62, asOf: Date()),
            MeasuredMetric(kind: .sleepHours, value: 7.2, asOf: Date()),
        ],
        asOf: Date(), authorized: true, available: true
    )

    static let healthBaselines: [HealthMetricKind: Double] = [
        .steps: 7600, .activeEnergy: 500, .exerciseMinutes: 32,
        .restingHeartRate: 56, .heartRateVariability: 65, .sleepHours: 7.0,
    ]

    /// A couple of weeks of varied entries so every surface (and the charts) has
    /// something real to show. Each entry carries ONE category, a clean title, and
    /// the user's own organized fields, no ranks, no estimated numbers.
    static func entries() -> [JournalEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [JournalEntry] = []

        struct Spec {
            let dayOffset: Int
            let hour: Int
            let source: EntrySource
            let raw: String
            let title: String
            let category: InsightCategory?
            let subtag: String?
            let fields: [(String, String)]
            let workout: WorkoutPayload?

            init(dayOffset: Int, hour: Int, source: EntrySource, raw: String, title: String,
                 category: InsightCategory?, subtag: String? = nil, fields: [(String, String)] = [],
                 workout: WorkoutPayload? = nil) {
                self.dayOffset = dayOffset
                self.hour = hour
                self.source = source
                self.raw = raw
                self.title = title
                self.category = category
                self.subtag = subtag
                self.fields = fields
                self.workout = workout
            }
        }

        // A logged movement helper for the sample workouts (resolves real muscles
        // from the library so the STYL muscle map has something to show).
        func logged(_ id: String, sets: Int, reps: Int? = nil, weight: Double? = nil) -> LoggedExercise {
            let ex = ExerciseLibrary.shared.exercise(id: id)
            let setList = (0..<max(sets, 1)).map { _ in ExerciseSet(reps: reps, weight: weight) }
            return LoggedExercise(exerciseID: id, name: ex?.name ?? id, sets: setList)
        }

        let specs: [Spec] = [
            .init(dayOffset: 0, hour: 8, source: .voice,
                  raw: "Slept maybe 5 hours, woke up sore.",
                  title: "Rough night of sleep", category: .sleep,
                  fields: [("Noting", "Last night's sleep"), ("Felt", "Tired")]),
            .init(dayOffset: 0, hour: 13, source: .text,
                  raw: "Chicken burrito for lunch.",
                  title: "Lunch burrito", category: .nutrition,
                  fields: [("Logging", "A meal"), ("When", "Lunch")]),
            .init(dayOffset: 1, hour: 18, source: .text,
                  raw: "Ran 3 miles after work, felt strong.",
                  title: "3-mile run", category: .activity,
                  fields: [("Did", "A walk or run"), ("Felt", "Moderate")]),
            .init(dayOffset: 1, hour: 21, source: .text,
                  raw: "Called my mom for an hour, good talk.",
                  title: "Call with mom", category: .social, subtag: "mother",
                  fields: [("Who", "Family"), ("How it went", "Great")]),
            .init(dayOffset: 2, hour: 7, source: .voice,
                  raw: "Slept like a rock, almost 8 and a half hours.",
                  title: "Deep night of sleep", category: .sleep,
                  fields: [("Noting", "Last night's sleep"), ("Felt", "Rested")]),
            .init(dayOffset: 2, hour: 9, source: .text,
                  raw: "Oatmeal with berries.",
                  title: "Oatmeal breakfast", category: .nutrition,
                  fields: [("Logging", "A meal"), ("When", "Breakfast")]),
            .init(dayOffset: 3, hour: 18, source: .text,
                  raw: "Push day. Bench felt strong.",
                  title: "Push day", category: .activity,
                  workout: WorkoutPayload(exercises: [
                    logged("barbell-bench-press", sets: 4, reps: 8, weight: 155),
                    logged("incline-dumbbell-press", sets: 3, reps: 10, weight: 60),
                    logged("cable-fly", sets: 3, reps: 12),
                    logged("triceps-pushdown", sets: 3, reps: 12, weight: 50),
                    logged("dumbbell-lateral-raise", sets: 3, reps: 15, weight: 15),
                  ], unit: .lb)),
            .init(dayOffset: 3, hour: 22, source: .text,
                  raw: "Feeling a bit overwhelmed with work lately.",
                  title: "Work stress", category: .mind,
                  fields: [("About", "Stress"), ("Right now", "Overwhelmed")]),
            .init(dayOffset: 4, hour: 12, source: .text,
                  raw: "Random idea for a side project, jot it down.",
                  title: "Side project idea", category: nil),
            .init(dayOffset: 5, hour: 9, source: .voice,
                  raw: "Easy 2 mile walk, drank lots of water.",
                  title: "Recovery walk", category: .activity,
                  fields: [("Did", "A walk or run"), ("Felt", "Easy")]),
            .init(dayOffset: 5, hour: 15, source: .text,
                  raw: "Slight headache this afternoon, took some water and rested.",
                  title: "Afternoon headache", category: .health,
                  fields: [("Noting", "A symptom"), ("Status", "Improving")]),
            .init(dayOffset: 7, hour: 8, source: .text,
                  raw: "Greek yogurt and granola.",
                  title: "Yogurt breakfast", category: .nutrition,
                  fields: [("Logging", "A meal"), ("When", "Breakfast")]),
            .init(dayOffset: 8, hour: 19, source: .text,
                  raw: "Cycled 12 miles after work.",
                  title: "Evening ride", category: .activity,
                  fields: [("Did", "A workout"), ("Felt", "Moderate")]),
            .init(dayOffset: 8, hour: 20, source: .text,
                  raw: "Dinner with friends, lots of laughs.",
                  title: "Dinner with friends", category: .social, subtag: "friends",
                  fields: [("Who", "Friends"), ("How it went", "Great")]),
            .init(dayOffset: 10, hour: 1, source: .voice,
                  raw: "Couldn't sleep, maybe 4 hours.",
                  title: "Trouble sleeping", category: .sleep,
                  fields: [("Noting", "Trouble sleeping"), ("Felt", "Exhausted")]),
            .init(dayOffset: 11, hour: 12, source: .text,
                  raw: "Yoga for 40 minutes, felt calm after.",
                  title: "Morning yoga", category: .activity,
                  fields: [("Did", "A workout"), ("Felt", "Easy")]),
            .init(dayOffset: 13, hour: 8, source: .text,
                  raw: "Felt calm and focused this morning.",
                  title: "Calm morning", category: .mind,
                  fields: [("About", "Mood"), ("Right now", "Calm")]),
        ]

        for spec in specs {
            let day = cal.date(byAdding: .day, value: -spec.dayOffset, to: today)!
            let created = cal.date(bySettingHour: spec.hour, minute: 0, second: 0, of: day)!
            let fields = spec.fields.map { EntryField(label: $0.0, value: $0.1) }
            result.append(
                JournalEntry(
                    id: UUID(),
                    userID: userID,
                    rawText: spec.raw,
                    source: spec.source,
                    status: .processed,
                    category: spec.category,
                    subtag: spec.subtag,
                    title: spec.title,
                    fields: fields,
                    workout: spec.workout,
                    createdAt: created,
                    entryDate: day,
                    syncedToCloud: true
                )
            )
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
