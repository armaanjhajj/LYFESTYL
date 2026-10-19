//
//  LabelFacts.swift
//  LYFESTYL
//
//  Numbers printed on a package, read from the photo's text. A label is the
//  best source there is, so when one is readable its numbers replace the
//  model's estimate outright. Handles both a Nutrition Facts panel ("Protein
//  30g") and front-of-pack claims ("30g PROTEIN", "150 CALORIES").
//
//  Pure parsing over recognized text lines, no Vision here, so it is testable.
//

import Foundation

nonisolated struct LabelFacts: Equatable, Sendable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    /// "1 bottle (340 mL)", from "Serving size ...".
    var servingSize: String?

    var isEmpty: Bool { calories == nil && protein == nil && carbs == nil && fat == nil }

    /// Parse recognized text, in reading order.
    init(lines: [String]) {
        // OCR splits "Calories" and "150" onto separate lines all the time, so
        // match across the joined text. Normalize the characters OCR varies on.
        let text = lines.joined(separator: " ")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()

        // Front-of-pack claims put marketing words between the number and the
        // nutrient: "30g HIGH QUALITY PROTEIN", "26 grams of complete protein".
        let filler = #"(?:(?:of|high|quality|complete|premium|plant|based|whey|milk|dairy|total|net|grams?)\s+){0,4}"#
        let grams = #"\s*(?:g|grams?)\b"#
        // OCR often reads a bold "g" as a period: "26. HIGH QUALITY PROTEIN".
        let claimGrams = #"\s*(?:g\b|grams?\b|\.(?=\s))"#
        // "PROTEIN 2g SUGAR": the 2g belongs to sugar, which has no amount of its
        // own. In a panel ("Total Fat 8g Saturated Fat 1g") the next nutrient
        // carries its own amount, so the 8g stays with total fat.
        let nextNutrient = #"(?:of\s+)?(?:added\s+|total\s+|dietary\s+|net\s+)?(?:sugars?|saturated\s+fat|trans\s+fat|fat|carbs?|carbohydrates?|fiber|fibre|sodium|cholesterol|protein)\b"#
        let ownAmount = #"\s*[:\-]?\s*\d{1,4}(?:\.\d)?\s*(?:g|mg|grams?)\b"#
        let ownedByNext = #"(?!\s+"# + nextNutrient + #"(?!"# + ownAmount + #"))"#

        // "150 CALORIES PER BOTTLE 8": the number before the word is the claim,
        // so that form goes first. A panel ("Calories 150") has no number there.
        calories = Self.first(in: text, patterns: [
            #"(?<![\d.])\b(\d{1,4})\s*(?:kcal|cal|calories)\b"#,
            #"calories\s*[:\-]?\s*(\d{1,4})\b"#,
        ], range: 0...2000)

        protein = Self.first(in: text, patterns: [
            #"protein\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + claimGrams + #"\s+"# + filler + #"protein\b"#,
        ], range: 0...150)

        carbs = Self.first(in: text, patterns: [
            #"total\s+carb(?:ohydrate|ohydrates|s)?\.?\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"(?<!net\s)\bcarb(?:ohydrate|ohydrates|s)\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + grams + #"\s+"# + filler + #"carb(?:ohydrate|ohydrates|s)?\b"#,
        ], range: 0...300)

        fat = Self.first(in: text, patterns: [
            #"total\s+fat\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"(?<!saturated\s)(?<!sat\.\s)(?<!trans\s)(?<!sat\s)\bfat\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + grams + #"\s+"# + filler + #"fat\b"#,
        ], range: 0...150)

        if let match = Self.capture(in: text, pattern: #"serving\s+size\s*[:\-]?\s*([^%]{1,40}?)(?=\s+(?:amount|servings|calories|per\s+container)|$)"#) {
            servingSize = match.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-.,")))
        }
    }

    /// Put the label's numbers on the food it belongs to. Text can't be pinned
    /// to one item in a photo of several, so this only applies when it's clear
    /// which food the label is: the one packaged item, or the only item.
    static func apply(_ facts: LabelFacts, to items: [(item: DraftItem, isPackaged: Bool)]) -> [DraftItem] {
        var result = items.map(\.item)
        guard !facts.isEmpty else { return result }
        let packaged = items.indices.filter { items[$0].isPackaged }
        let target: Int? = packaged.count == 1 ? packaged[0] : (items.count == 1 ? 0 : nil)
        guard let target else { return result }

        var food = result[target].food
        food.servings = 1
        if let value = facts.calories { food.base.calories = value }
        if let value = facts.protein { food.base.protein = value }
        if let value = facts.carbs { food.base.carbs = value }
        if let value = facts.fat { food.base.fat = value }
        if let size = facts.servingSize, !size.isEmpty { food.portion = size }
        result[target].food = food
        result[target].confidence = .high
        result[target].alternatives = []
        return result
    }

    // MARK: - Matching

    private static func first(in text: String, patterns: [String], range: ClosedRange<Double>) -> Double? {
        for pattern in patterns {
            if let raw = capture(in: text, pattern: pattern), let value = Double(raw), range.contains(value) {
                return value
            }
        }
        return nil
    }

    private static func capture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
