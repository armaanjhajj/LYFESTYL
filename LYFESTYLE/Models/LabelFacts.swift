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
        // OCR on curved bottles misspells and clips words: "Proteln 30g",
        // "SPROTEIN", "drate 4g" for "Total Carbohydrate 4g".
        let proteinWord = #"[a-z]?prot[a-z1]{1,3}ns?"#
        let carbWord = #"(?:carb(?:ohydrate|ohydrates|s)?|[a-z]*hydrates?|[a-z]*drates?)"#
        let ownAmount = #"\s*[:\-]?\s*\d{1,4}(?:\.\d)?\s*(?:g|mg|grams?)\b"#
        let ownedByNext = #"(?!\s+"# + nextNutrient + #"(?!"# + ownAmount + #"))"#

        // "150 CALORIES PER BOTTLE 8": the number before the word is the claim,
        // so that form goes first. A panel ("Calories 150") has no number there.
        calories = Self.first(in: text, patterns: [
            #"(?<![\d.])\b(\d{1,4})\s*(?:kcal|cal|calories)\b"#,
            #"calories\s*[:\-]?\s*(\d{1,4})\b"#,
        ], range: 0...2000)

        protein = Self.first(in: text, patterns: [
            #"\b"# + proteinWord + #"\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + claimGrams + #"\s+"# + filler + proteinWord + #"\b"#,
            // Read sideways, the "g" often drops off: "30 | PROTEIN".
            #"(?<![\d.])\b(\d{1,3})\s+"# + proteinWord + #"\b"#,
        ], range: 0...150)

        carbs = Self.first(in: text, patterns: [
            #"total\s+carb(?:ohydrate|ohydrates|s)?\.?\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"(?<!net\s)\b"# + carbWord + #"\.?\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + grams + #"\s+"# + filler + carbWord + #"\b"#,
        ], range: 0...300)

        fat = Self.first(in: text, patterns: [
            #"total\s+fat\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"(?<!saturated\s)(?<!sat\.\s)(?<!trans\s)(?<!sat\s)\bfat\s*[:\-]?\s*(\d{1,3}(?:\.\d)?)"# + grams + ownedByNext,
            #"\b(\d{1,3}(?:\.\d)?)"# + grams + #"\s+"# + filler + #"fat\b"#,
        ], range: 0...150)

        if let match = Self.capture(in: text, pattern: #"serving\s+size\s*[:\-]?\s*([^()%]{1,30}?\([^)]{1,20}\)|[^%]{1,40}?(?=\s+(?:a?mount|servings|calories|per\s+container)|$))"#) {
            servingSize = match.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-.,")))
        }
    }

    /// One food from a scan, with the identity the person never sees.
    struct Candidate: Equatable, Sendable {
        var item: DraftItem
        var isPackaged: Bool
        /// Brand and product line, empty for unpackaged food.
        var product: String = ""

        var looksPackaged: Bool { isPackaged || !product.isEmpty }
    }

    /// Put the label's numbers on the food the label belongs to: the one
    /// packaged item, the only item, or, with several, the product the label's
    /// text matches best ("fairlife nutrition plan" over a Dunkin cup).
    static func apply(_ facts: LabelFacts, to candidates: [Candidate], labelLines: [String]) -> [DraftItem] {
        var result = candidates.map(\.item)
        guard !facts.isEmpty, let target = labelOwner(in: candidates, labelLines: labelLines) else { return result }

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

    /// The model sometimes lists a word printed on a package ("chocolate",
    /// "vanilla") as a separate food. When a packaged product is in the photo,
    /// any other item whose whole name is printed in the label text is dropped.
    static func removeLabelWords(from candidates: [Candidate], labelLines: [String]) -> [Candidate] {
        let text = labelLines.joined(separator: " ").lowercased()
        guard !text.isEmpty, candidates.count > 1,
              let owner = labelOwner(in: candidates, labelLines: labelLines) else { return candidates }
        return candidates.enumerated().compactMap { index, candidate in
            let name = candidate.item.food.name.trimmingCharacters(in: .whitespaces).lowercased()
            let isLabelWord = index != owner && !candidate.looksPackaged && name.count > 2 && text.contains(name)
            return isLabelWord ? nil : candidate
        }
    }

    /// Which candidate a label's text belongs to, if that's clear.
    static func labelOwner(in candidates: [Candidate], labelLines: [String]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let packaged = candidates.indices.filter { candidates[$0].looksPackaged }
        if packaged.count == 1 { return packaged[0] }
        if candidates.count == 1 { return 0 }

        let text = labelLines.joined(separator: " ").lowercased()
        func score(_ i: Int) -> Int {
            let identity = candidates[i].product.isEmpty ? candidates[i].item.food.name : candidates[i].product
            return identity.lowercased().split(separator: " ").filter { $0.count > 2 && text.contains($0) }.count
        }
        let pool = packaged.isEmpty ? Array(candidates.indices) : packaged
        let scores = pool.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }
        guard let best = scores.first, best.1 >= 2 else { return nil }
        if scores.count > 1, scores[1].1 == best.1 { return nil }
        return best.0
    }

    /// Flavors the model sometimes returns as if they were the food.
    private static let flavors: Set<String> = [
        "chocolate", "vanilla", "strawberry", "caramel", "mocha", "original", "banana",
        "cookies and cream", "cookies & cream", "salted caramel", "peanut butter", "mint",
        "berry", "mixed berry", "unflavored", "plain", "cherry", "lemon", "orange",
    ]

    /// Product types worth naming a package by, most specific first.
    private static let kinds: [(needs: [String], name: String)] = [
        (["protein", "shake"], "Protein shake"), (["protein", "bar"], "Protein bar"),
        (["protein", "drink"], "Protein drink"), (["energy", "drink"], "Energy drink"),
        (["smoothie"], "Smoothie"), (["shake"], "Shake"), (["yogurt"], "Yogurt"),
        (["granola"], "Granola bar"), (["cold", "brew"], "Cold brew"), (["latte"], "Latte"),
        (["coffee"], "Coffee"), (["tea"], "Tea"), (["juice"], "Juice"), (["soda"], "Soda"),
        (["sparkling"], "Sparkling water"), (["chips"], "Chips"), (["crackers"], "Crackers"),
        (["cookies"], "Cookies"), (["cereal"], "Cereal"), (["milk"], "Milk"), (["bar"], "Bar"),
    ]

    /// Give a packaged item that came back named as a flavor ("Chocolate") the
    /// name of its product type, read off its own label ("NUTRITION SHAKE" plus
    /// "PROTEIN" is a protein shake).
    static func nameKinds(_ candidates: [Candidate], labelLines: [String]) -> [Candidate] {
        let words = Set(labelLines.joined(separator: " ").lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard !words.isEmpty else { return candidates }
        let kind = kinds.first { $0.needs.allSatisfy(words.contains) }?.name
        return candidates.map { candidate in
            guard candidate.looksPackaged, let kind,
                  flavors.contains(candidate.item.food.name.lowercased()) else { return candidate }
            var renamed = candidate
            renamed.item.food.name = kind
            return renamed
        }
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
