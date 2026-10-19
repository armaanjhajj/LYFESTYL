//
//  FoodScan.swift
//  LYFESTYL
//
//  The guided-generation schema. Foundation Models fills these structs directly,
//  no JSON in between. Property order is generation order, so each food is
//  first identified (packaged or not, and which product), then given a plain
//  name, sized, and counted: the portion is decided before the numbers that
//  depend on it. The product identity stays behind the scenes; people see the
//  plain name.
//

import Foundation
import FoundationModels

@Generable
nonisolated struct FoodScan {
    @Guide(description: "Every distinct food or drink, one entry each. A burger and fries are two items; a sandwich is one item. Empty if there is no food or drink.", .maximumCount(8))
    var items: [ScannedFood]
}

@Generable
nonisolated struct ScannedFood {
    @Guide(description: "true only for a packaged product whose label is visible")
    var isPackaged: Bool

    @Guide(description: "For a packaged product, its brand and product line as printed, at most 5 words. Empty otherwise. Never shown to the person.")
    var product: String

    @Guide(description: "What a person would call it, 1 to 3 words, no brand, no numbers, like 'Protein shake', 'Iced coffee', 'Chicken salad'")
    var name: String

    @Guide(description: "The amount in everyday units, like '1 bottle', '1 cup', '6 oz', '2 slices'")
    var portion: String

    @Guide(description: "Kilocalories for that whole amount", .range(0...3000))
    var calories: Int

    @Guide(description: "Grams of protein for that amount", .range(0...250))
    var protein: Int

    @Guide(description: "Grams of carbohydrate for that amount", .range(0...400))
    var carbs: Int

    @Guide(description: "Grams of fat for that amount", .range(0...250))
    var fat: Int

    @Guide(description: "high when the food and amount are clear, medium when fairly sure, low when the food is ambiguous, hidden, or hard to see")
    var confidence: ScanConfidence

    @Guide(description: "When confidence is not high, up to 3 other foods this could be, most likely first. Empty when confidence is high.", .maximumCount(3))
    var alternatives: [String]
}

@Generable
nonisolated enum ScanConfidence {
    case high, medium, low

    var confidence: Confidence {
        switch self {
        case .high:   .high
        case .medium: .medium
        case .low:    .low
        }
    }
}

extension ScannedFood {
    nonisolated var draftItem: DraftItem {
        let name = Self.plainName(self.name)
        return DraftItem(
            food: FoodItem(
                name: name,
                portion: portion.trimmingCharacters(in: .whitespacesAndNewlines),
                base: Nutrition(
                    calories: Double(max(0, calories)),
                    protein: Double(max(0, protein)),
                    carbs: Double(max(0, carbs)),
                    fat: Double(max(0, fat))
                )
            ),
            confidence: confidence.confidence,
            alternatives: alternatives
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(self.name) != .orderedSame }
        )
    }

    /// A short, plain display name even when the model is wordy: it ends where
    /// a quantity starts ("Chicken salad 2 cups"), has at most four words, and
    /// is capitalized like a title.
    nonisolated static func plainName(_ raw: String) -> String {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let firstNumber = tokens.firstIndex { $0.contains(where: \.isNumber) }
        let kept = firstNumber.map { $0 > 0 ? Array(tokens[..<$0]) : tokens.filter { !$0.contains(where: \.isNumber) } } ?? tokens
        let words = kept.prefix(4)
        let name = words.joined(separator: " ")
        guard !name.isEmpty else { return "Food" }
        if name == name.lowercased() || name == name.uppercased() { return name.capitalized }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// A food mid-generation. Fields fill in as the model writes them, so the
/// drawer can show each food arrive and its numbers count up.
nonisolated struct StreamedFood: Identifiable, Equatable, Sendable {
    let id: Int
    var name: String
    var portion: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    /// Fat is the last number written for a food.
    var hasNumbers: Bool { fat != nil }

    init?(_ partial: ScannedFood.PartiallyGenerated, index: Int) {
        guard let raw = partial.name?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count > 1 else { return nil }
        id = index
        name = ScannedFood.plainName(raw)
        portion = partial.portion.flatMap { $0.isEmpty ? nil : $0 }
        calories = partial.calories.map(Double.init)
        protein = partial.protein.map(Double.init)
        carbs = partial.carbs.map(Double.init)
        fat = partial.fat.map(Double.init)
    }
}
