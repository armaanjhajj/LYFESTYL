//
//  Nutrition.swift
//  LYFESTYL
//
//  The value types every surface shares: a nutrition total, one food, and the
//  model's confidence in a food it spotted.
//

import Foundation

/// Calories and the three macros, in kcal and grams.
nonisolated struct Nutrition: Hashable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Nutrition(calories: 0, protein: 0, carbs: 0, fat: 0)

    subscript(macro: Macro) -> Double {
        switch macro {
        case .calories: calories
        case .protein:  protein
        case .carbs:    carbs
        case .fat:      fat
        }
    }

    func scaled(by factor: Double) -> Nutrition {
        Nutrition(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }
}

extension Sequence where Element == Nutrition {
    nonisolated var total: Nutrition { reduce(.zero, +) }
}

/// One food in a meal. `base` is the nutrition for one `portion`; `servings`
/// scales it, so "2 slices" at 1.5× reads as three slices without the user
/// retyping numbers.
nonisolated struct FoodItem: Identifiable, Hashable, Sendable {
    /// Session-only identity for lists. Not stored: an id per food would cost
    /// more bytes than the rest of the record, and nothing outside a meal ever
    /// points at a single food.
    var id = UUID()
    var name: String
    var portion: String
    var servings: Double = 1
    var base: Nutrition

    var nutrition: Nutrition { base.scaled(by: servings) }

    /// "1 cup" or "1 cup × 1.5"
    var portionDescription: String {
        let portion = portion.isEmpty ? "1 serving" : portion
        return servings == 1 ? portion : "\(portion) × \(Formatting.servings(servings).dropLast())"
    }
}

// Stored inside a meal record as a binary plist with one-letter keys. A typical
// item encodes to well under 100 bytes. Servings is only written when it is
// not 1, which it usually is.
extension FoodItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case name = "n", portion = "p", servings = "s"
        case calories = "k", protein = "r", carbs = "c", fat = "f"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        portion = try c.decodeIfPresent(String.self, forKey: .portion) ?? ""
        servings = try c.decodeIfPresent(Double.self, forKey: .servings) ?? 1
        base = Nutrition(
            calories: try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0,
            protein: try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0,
            carbs: try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0,
            fat: try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        if !portion.isEmpty { try c.encode(portion, forKey: .portion) }
        if servings != 1 { try c.encode(servings, forKey: .servings) }
        try c.encode(base.calories.rounded(), forKey: .calories)
        try c.encode(base.protein.rounded(), forKey: .protein)
        try c.encode(base.carbs.rounded(), forKey: .carbs)
        try c.encode(base.fat.rounded(), forKey: .fat)
    }
}

extension Array where Element == FoodItem {
    nonisolated var nutrition: Nutrition { map(\.nutrition).total }

    /// "Chicken, rice", or "Chicken, rice + 2 more".
    nonisolated var title: String {
        guard !isEmpty else { return "Meal" }
        let names = prefix(2).map(\.name)
        let rest = count - names.count
        return names.joined(separator: ", ") + (rest > 0 ? " + \(rest) more" : "")
    }

    /// Compact binary encoding for storage.
    nonisolated func encoded() -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return (try? encoder.encode(self)) ?? Data()
    }

    nonisolated init(decoding data: Data) {
        self = (try? PropertyListDecoder().decode([FoodItem].self, from: data)) ?? []
    }
}

/// How sure the model was about a food it spotted. Only lives on drafts; once
/// logged, a food is just a food.
nonisolated enum Confidence: Int, Comparable, Sendable {
    case low, medium, high

    static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A food on the review drawer: the item plus what the model thought of it.
nonisolated struct DraftItem: Identifiable, Hashable, Sendable {
    var food: FoodItem
    /// nil for foods the user picked or typed themselves.
    var confidence: Confidence?
    /// Other things the model thought this could be, most likely first.
    var alternatives: [String] = []

    var id: UUID { food.id }
    var needsCheck: Bool { confidence == .low }
}
