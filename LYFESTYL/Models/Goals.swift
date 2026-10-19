//
//  Goals.swift
//  LYFESTYL
//
//  Daily targets, and the body profile that can suggest them. Both are tiny and
//  belong to the person rather than the device, so they sync through iCloud
//  key-value storage (see `GoalStore`) instead of the meal database.
//

import Foundation

nonisolated struct Goals: Codable, Hashable, Sendable {
    var calories: Double = 2000
    var protein: Double = 140
    var carbs: Double = 220
    var fat: Double = 65

    subscript(macro: Macro) -> Double {
        get {
            switch macro {
            case .calories: calories
            case .protein:  protein
            case .carbs:    carbs
            case .fat:      fat
            }
        }
        set {
            switch macro {
            case .calories: calories = newValue
            case .protein:  protein = newValue
            case .carbs:    carbs = newValue
            case .fat:      fat = newValue
            }
        }
    }

    /// Sensible bounds for each goal's editor.
    static func range(for macro: Macro) -> ClosedRange<Double> {
        switch macro {
        case .calories: 1000...6000
        case .protein:  20...400
        case .carbs:    20...800
        case .fat:      20...300
        }
    }

    static func step(for macro: Macro) -> Double { macro == .calories ? 50 : 5 }
}

/// What the goal calculator needs. Canonical units (kg, cm, years).
nonisolated struct BodyProfile: Codable, Hashable, Sendable {
    enum Sex: String, Codable, CaseIterable, Sendable { case female, male }

    enum Activity: String, Codable, CaseIterable, Sendable {
        case sedentary, light, moderate, active, veryActive

        var label: String {
            switch self {
            case .sedentary:  "Mostly sitting"
            case .light:      "Lightly active"
            case .moderate:   "Moderately active"
            case .active:     "Active"
            case .veryActive: "Very active"
            }
        }

        var detail: String {
            switch self {
            case .sedentary:  "Desk job, little exercise"
            case .light:      "Exercise 1 to 3 days a week"
            case .moderate:   "Exercise 3 to 5 days a week"
            case .active:     "Hard exercise 6 to 7 days a week"
            case .veryActive: "Physical job or training twice a day"
            }
        }

        var multiplier: Double {
            switch self {
            case .sedentary:  1.2
            case .light:      1.375
            case .moderate:   1.55
            case .active:     1.725
            case .veryActive: 1.9
            }
        }
    }

    enum Aim: String, Codable, CaseIterable, Sendable {
        case lose, maintain, gain

        var label: String {
            switch self {
            case .lose:     "Lose weight"
            case .maintain: "Maintain"
            case .gain:     "Build muscle"
            }
        }

        /// Daily calorie adjustment from maintenance. About 0.5 kg a week down,
        /// or a lean surplus up.
        var calorieDelta: Double {
            switch self {
            case .lose:     -500
            case .maintain: 0
            case .gain:     300
            }
        }

        /// Protein per kg of body weight.
        var proteinPerKg: Double {
            switch self {
            case .lose:     2.0
            case .maintain: 1.6
            case .gain:     1.8
            }
        }
    }

    var sex: Sex = .female
    var age: Int = 30
    var heightCm: Double = 168
    var weightKg: Double = 68
    var activity: Activity = .light
    var aim: Aim = .maintain

    /// Mifflin-St Jeor resting energy, the formula most dietitians reach for.
    var restingCalories: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    var maintenanceCalories: Double { restingCalories * activity.multiplier }

    /// Calories from maintenance plus the aim, floored at a safe minimum; protein
    /// from body weight; fat at 27% of calories; carbs take the rest.
    var suggestedGoals: Goals {
        let floor: Double = sex == .male ? 1500 : 1200
        let calories = max(floor, maintenanceCalories + aim.calorieDelta)
        let protein = min(weightKg * aim.proteinPerKg, calories * 0.35 / 4)
        let fat = calories * 0.27 / 9
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        return Goals(
            calories: (calories / 10).rounded() * 10,
            protein: protein.rounded(),
            carbs: carbs.rounded(),
            fat: fat.rounded()
        )
    }
}
