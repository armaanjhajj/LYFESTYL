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

    /// A couple of weeks of varied entries so every surface (and the charts) has
    /// something real to show.
    static func entries() -> [JournalEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [JournalEntry] = []

        struct Spec {
            let dayOffset: Int
            let hour: Int
            let source: EntrySource
            let raw: String
            let summary: String
            let insights: [(InsightCategory, Rank, String, String, [MetricKey: Double])]
        }

        let specs: [Spec] = [
            .init(dayOffset: 0, hour: 8, source: .voice,
                  raw: "Woke up sore in my lower back, slept maybe 5 hours. Had black coffee and two eggs.",
                  summary: "Rough sleep and a sore back, but a light protein breakfast.",
                  insights: [
                    (.sleep, .bad, "Short, restless night", "About 5 hours — under what you need to recover.", [.sleepHours: 5]),
                    (.nutrition, .good, "Eggs + black coffee", "Lean protein start, low calories.", [.calories: 200, .proteinGrams: 12, .fatGrams: 11, .carbsGrams: 1]),
                    (.health, .okay, "Lower back soreness", "Mild soreness noted; nothing severe.", [:]),
                  ]),
            .init(dayOffset: 0, hour: 13, source: .text,
                  raw: "Ran 3 miles at lunch, felt strong. Then crushed a chicken burrito.",
                  summary: "Strong midday run followed by a big burrito.",
                  insights: [
                    (.activity, .excellent, "3-mile run", "Solid sustained cardio at midday.", [.activeMinutes: 28, .distanceMiles: 3]),
                    (.nutrition, .okay, "Chicken burrito", "Big portion — decent protein, heavy on carbs.", [.calories: 850, .proteinGrams: 40, .carbsGrams: 95, .fatGrams: 28]),
                  ]),
            .init(dayOffset: 1, hour: 22, source: .text,
                  raw: "Ate pizza and ice cream for dinner, total junk. No workout today.",
                  summary: "Indulgent dinner and a rest day.",
                  insights: [
                    (.nutrition, .bad, "Pizza + ice cream", "High calorie, high fat, low protein.", [.calories: 1400, .proteinGrams: 35, .carbsGrams: 150, .fatGrams: 60]),
                    (.activity, .awful, "No movement", "No exercise logged today.", [.activeMinutes: 0]),
                  ]),
            .init(dayOffset: 2, hour: 7, source: .voice,
                  raw: "Slept like a rock, almost 8 and a half hours. Oatmeal with berries.",
                  summary: "Great sleep and a clean breakfast.",
                  insights: [
                    (.sleep, .excellent, "Deep 8.5h sleep", "Full restorative night.", [.sleepHours: 8.5]),
                    (.nutrition, .excellent, "Oatmeal + berries", "Balanced, fiber-rich start.", [.calories: 320, .proteinGrams: 10, .carbsGrams: 58, .fatGrams: 6]),
                  ]),
            .init(dayOffset: 3, hour: 18, source: .text,
                  raw: "Lifted weights for an hour, drank a protein shake. Felt great.",
                  summary: "Solid strength session with post-workout protein.",
                  insights: [
                    (.activity, .excellent, "1h strength session", "Full hour of resistance training.", [.activeMinutes: 60]),
                    (.nutrition, .good, "Protein shake", "Clean recovery fuel.", [.calories: 250, .proteinGrams: 30, .carbsGrams: 12, .fatGrams: 4]),
                    (.health, .excellent, "Feeling strong", "Reported feeling great.", [:]),
                  ]),
            .init(dayOffset: 4, hour: 23, source: .text,
                  raw: "Worked late, only 6 hours sleep. Skipped lunch, big late dinner.",
                  summary: "Long workday, skipped meals, short sleep.",
                  insights: [
                    (.sleep, .okay, "6 hours", "A bit short from a late night.", [.sleepHours: 6]),
                    (.nutrition, .bad, "Skipped lunch, big dinner", "Irregular eating, calorie-dense at night.", [.calories: 1100, .proteinGrams: 45, .carbsGrams: 110, .fatGrams: 48]),
                  ]),
            .init(dayOffset: 5, hour: 9, source: .voice,
                  raw: "Easy 2 mile walk, lots of water. Feeling recovered.",
                  summary: "Light recovery walk and good hydration.",
                  insights: [
                    (.activity, .good, "2-mile walk", "Easy active recovery.", [.activeMinutes: 35, .distanceMiles: 2]),
                    (.nutrition, .good, "Plenty of water", "Well hydrated.", [.waterOunces: 80]),
                    (.health, .good, "Recovered", "Feeling back to normal.", [:]),
                  ]),
            .init(dayOffset: 7, hour: 8, source: .text,
                  raw: "Slept 7.5 hours. Greek yogurt and granola for breakfast.",
                  summary: "Good sleep and a balanced breakfast.",
                  insights: [
                    (.sleep, .good, "7.5 hours", "Right in the healthy range.", [.sleepHours: 7.5]),
                    (.nutrition, .good, "Yogurt + granola", "Protein and whole grains.", [.calories: 380, .proteinGrams: 22, .carbsGrams: 48, .fatGrams: 10]),
                  ]),
            .init(dayOffset: 8, hour: 19, source: .text,
                  raw: "Cycled 12 miles after work. Salmon and veggies for dinner.",
                  summary: "Long ride and a clean, balanced dinner.",
                  insights: [
                    (.activity, .excellent, "12-mile ride", "Strong endurance effort.", [.activeMinutes: 55, .distanceMiles: 12]),
                    (.nutrition, .excellent, "Salmon + veggies", "Lean protein and vegetables.", [.calories: 600, .proteinGrams: 42, .carbsGrams: 30, .fatGrams: 30]),
                  ]),
            .init(dayOffset: 10, hour: 1, source: .voice,
                  raw: "Couldn't sleep, maybe 4 hours. Stress headache all day.",
                  summary: "Bad night and a stress headache.",
                  insights: [
                    (.sleep, .awful, "Only ~4 hours", "Badly disrupted night.", [.sleepHours: 4]),
                    (.health, .bad, "Stress headache", "Persistent headache reported.", [:]),
                  ]),
            .init(dayOffset: 11, hour: 12, source: .text,
                  raw: "Yoga for 40 minutes, big salad with chicken for lunch.",
                  summary: "Calm yoga session and a healthy lunch.",
                  insights: [
                    (.activity, .good, "40 min yoga", "Mobility and core work.", [.activeMinutes: 40]),
                    (.nutrition, .excellent, "Chicken salad", "Lean and vegetable-forward.", [.calories: 450, .proteinGrams: 38, .carbsGrams: 25, .fatGrams: 18]),
                  ]),
            .init(dayOffset: 13, hour: 8, source: .text,
                  raw: "Slept 8 hours. Two coffees, no breakfast. Walked the dog a mile.",
                  summary: "Great sleep, skipped breakfast, short walk.",
                  insights: [
                    (.sleep, .excellent, "8 hours", "Full night of rest.", [.sleepHours: 8]),
                    (.activity, .okay, "1-mile dog walk", "Light movement.", [.activeMinutes: 18, .distanceMiles: 1]),
                    (.nutrition, .okay, "Coffee, no breakfast", "Low morning intake.", [.calories: 40]),
                  ]),
        ]

        for spec in specs {
            let day = cal.date(byAdding: .day, value: -spec.dayOffset, to: today)!
            let created = cal.date(bySettingHour: spec.hour, minute: 0, second: 0, of: day)!
            let entryID = UUID()
            let insights = spec.insights.map { (cat, rank, title, detail, metrics) in
                Insight(
                    entryID: entryID,
                    category: cat,
                    rank: rank,
                    title: title,
                    detail: detail,
                    calories: metrics[.calories].map { Int($0) },
                    proteinGrams: metrics[.proteinGrams].map { Int($0) },
                    carbsGrams: metrics[.carbsGrams].map { Int($0) },
                    fatGrams: metrics[.fatGrams].map { Int($0) },
                    waterOunces: metrics[.waterOunces].map { Int($0) },
                    activeMinutes: metrics[.activeMinutes].map { Int($0) },
                    distanceMiles: metrics[.distanceMiles],
                    sleepHours: metrics[.sleepHours],
                    createdAt: created,
                    entryDate: day
                )
            }
            result.append(
                JournalEntry(
                    id: entryID,
                    userID: userID,
                    rawText: spec.raw,
                    source: spec.source,
                    status: .processed,
                    overallSummary: spec.summary,
                    createdAt: created,
                    entryDate: day,
                    insights: insights,
                    syncedToCloud: true
                )
            )
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
