//
//  HabitEngine.swift
//  LYFESTYL
//
//  Daily totals and the habit flags on the dashboard. Plain arithmetic over
//  logged meals, no model involved, so a flag always has a reason the person
//  can check: "under your goal on 4 of the last 6 days".
//
//  Only finished days count (today is still in progress), and only days with
//  at least one meal (an empty day means nothing was logged, not nothing eaten).
//

import Foundation

/// One calendar day's totals.
nonisolated struct DayTotal: Identifiable, Hashable, Sendable {
    let day: Date
    var nutrition: Nutrition
    var mealCount: Int

    var id: Date { day }
}

nonisolated struct Habit: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case lowProtein, highCarbs, highFat, highCalories, lowCalories, onTrack
    }

    let kind: Kind
    let macro: Macro
    let title: String
    let detail: String

    var id: Kind { kind }
    var isPositive: Bool { kind == .onTrack }

    var symbol: String {
        switch kind {
        case .lowProtein, .lowCalories:              "arrow.down.right"
        case .highCarbs, .highFat, .highCalories:    "arrow.up.right"
        case .onTrack:                               "checkmark.seal.fill"
        }
    }
}

nonisolated enum HabitEngine {

    /// How far back habits look.
    static let windowDays = 7
    /// Below this many logged days there isn't a pattern yet.
    static let minimumDays = 3

    enum Result: Equatable, Sendable {
        case notEnoughData(loggedDays: Int)
        case habits([Habit])
    }

    /// Group meals into calendar days, newest first.
    static func dailyTotals(
        _ meals: [(date: Date, nutrition: Nutrition)],
        calendar: Calendar = .current
    ) -> [DayTotal] {
        var byDay: [Date: DayTotal] = [:]
        for meal in meals {
            let day = calendar.startOfDay(for: meal.date)
            var total = byDay[day] ?? DayTotal(day: day, nutrition: .zero, mealCount: 0)
            total.nutrition = total.nutrition + meal.nutrition
            total.mealCount += 1
            byDay[day] = total
        }
        return byDay.values.sorted { $0.day > $1.day }
    }

    static func evaluate(
        days: [DayTotal],
        goals: Goals,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: today) else {
            return .notEnoughData(loggedDays: 0)
        }
        let window = days.filter { $0.day >= start && $0.day < today && $0.mealCount > 0 }
        guard window.count >= minimumDays else { return .notEnoughData(loggedDays: window.count) }

        let n = window.count
        // A habit is most of the logged days, not a single off day.
        let threshold = max(2, Int((Double(n) / 2).rounded(.up)))

        func count(_ test: (Nutrition) -> Bool) -> Int { window.filter { test($0.nutrition) }.count }
        func average(_ macro: Macro) -> Double { window.map { $0.nutrition[macro] }.reduce(0, +) / Double(n) }
        func of(_ k: Int) -> String { "\(k) of the last \(n) days you logged" }

        var habits: [Habit] = []

        let lowProtein = count { $0.protein < goals.protein * 0.8 }
        if lowProtein >= threshold {
            habits.append(Habit(
                kind: .lowProtein, macro: .protein,
                title: "Protein has been low",
                detail: "Under your \(Formatting.grams(goals.protein)) goal on \(of(lowProtein)), averaging \(Formatting.grams(average(.protein)))."
            ))
        }

        let highCarbs = count { $0.carbs > goals.carbs * 1.15 }
        if highCarbs >= threshold {
            habits.append(Habit(
                kind: .highCarbs, macro: .carbs,
                title: "Carbs are running high",
                detail: "Over your \(Formatting.grams(goals.carbs)) goal on \(of(highCarbs)), averaging \(Formatting.grams(average(.carbs)))."
            ))
        }

        let highFat = count { $0.fat > goals.fat * 1.2 }
        if highFat >= threshold {
            habits.append(Habit(
                kind: .highFat, macro: .fat,
                title: "Fat is running high",
                detail: "Over your \(Formatting.grams(goals.fat)) goal on \(of(highFat)), averaging \(Formatting.grams(average(.fat)))."
            ))
        }

        let highCalories = count { $0.calories > goals.calories * 1.1 }
        let lowCalories = count { $0.calories < goals.calories * 0.7 }
        if highCalories >= threshold {
            habits.append(Habit(
                kind: .highCalories, macro: .calories,
                title: "Calories are over goal",
                detail: "Over \(Formatting.calories(goals.calories)) kcal on \(of(highCalories)), averaging \(Formatting.calories(average(.calories))) kcal."
            ))
        } else if lowCalories >= threshold {
            habits.append(Habit(
                kind: .lowCalories, macro: .calories,
                title: "Calories are well under goal",
                detail: "Under 70% of your goal on \(of(lowCalories)). If that isn't on purpose, some meals may be missing from your log."
            ))
        }

        if habits.isEmpty {
            let onTarget = count { abs($0.calories - goals.calories) <= goals.calories * 0.1 }
            habits.append(Habit(
                kind: .onTrack, macro: .calories,
                title: "Nothing stands out",
                detail: onTarget > 0
                    ? "Calories were within 10% of your goal on \(of(onTarget)), and your macros look balanced."
                    : "Your macros look balanced across the last \(n) days you logged."
            ))
        }
        return .habits(habits)
    }
}
