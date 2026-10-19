//
//  FoodScan.swift
//  LYFESTYL
//
//  The guided-generation schema. Foundation Models fills these structs directly,
//  no JSON in between. Property order is generation order, so each food is
//  first marked packaged or not (which decides how it should be named), then
//  named, sized, and counted: the portion is decided before the numbers that
//  depend on it.
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
    @Guide(description: "true only for a packaged or branded product whose packaging is visible")
    var isPackaged: Bool

    @Guide(description: "For a packaged product, the brand and product exactly as printed. Otherwise a short everyday name, like 'Grilled chicken breast'.")
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
        DraftItem(
            food: FoodItem(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
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
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(name) != .orderedSame }
        )
    }
}
