//
//  EntryBreakdown.swift
//  LYFESTYL
//
//  Guided Generation schema (CLAUDE.md §1). The on-device Foundation Models
//  framework returns these typed Swift values directly — NO JSON parsing. We
//  keep the schema focused (the ~3B model is tuned for extraction), use fixed
//  optional metric fields for trend comparability, and constrain `category` and
//  `rank` with `.anyOf` so they always map cleanly to our enums.
//
//  Schema version: 1  (see InsightSchema.version). If these fields change,
//  bump the version so older entries stay comparable.
//

import FoundationModels

/// Top-level result for one journal entry.
@Generable
struct EntryBreakdown: Equatable {
    @Guide(description: "One short, plain-language sentence summarizing the whole entry, in a neutral first-person-adjacent voice. No preamble, no 'The user'. e.g. 'Tough morning but a solid workout and a junk-food lunch.'")
    var overallSummary: String

    @Guide(description: "One element for EACH lifestyle category the entry actually touches. Omit categories that are not mentioned. Never invent food, exercise, or sleep that the entry did not describe.")
    var categories: [CategoryInsight]
}

/// One category's breakdown of the entry. A single entry can produce several.
@Generable
struct CategoryInsight: Equatable {
    @Guide(description: "Which lifestyle category this insight covers.", .anyOf(["NUTRITION", "ACTIVITY", "SLEEP", "HEALTH"]))
    var category: String

    @Guide(description: "Quality rank for this category in this entry. Use the rubric: NUTRITION EXCELLENT=balanced whole foods/appropriate calories, AWFUL=very poor/excessive. ACTIVITY EXCELLENT=vigorous sustained exercise, AWFUL=none when intended or pain-limited. SLEEP EXCELLENT≈7.5-9h restful, AWFUL=<4h or badly disrupted. HEALTH EXCELLENT=feeling great/no symptoms, AWFUL=ill/injured/severe symptoms.", .anyOf(["EXCELLENT", "GOOD", "OKAY", "BAD", "AWFUL"]))
    var rank: String

    @Guide(description: "A 3 to 6 word headline of what was logged for this category. e.g. 'Ran a mile, hit gym' or 'Donut and pizza'.")
    var title: String

    @Guide(description: "One or two plain sentences: the tangible estimate and the reason for this rank. Be concrete; do not give medical advice or diagnoses.")
    var detail: String

    // MARK: Nutrition metrics — fill only for NUTRITION, otherwise leave nil.
    @Guide(description: "Estimated total calories consumed across food and drink in this entry. Nil if this is not a nutrition insight or there is nothing to estimate.")
    var calories: Int?
    @Guide(description: "Estimated grams of protein consumed. Nil if unknown or not nutrition.")
    var proteinGrams: Int?
    @Guide(description: "Estimated grams of carbohydrates consumed. Nil if unknown or not nutrition.")
    var carbsGrams: Int?
    @Guide(description: "Estimated grams of fat consumed. Nil if unknown or not nutrition.")
    var fatGrams: Int?
    @Guide(description: "Estimated water intake in fluid ounces, if hydration was mentioned. Nil otherwise.")
    var waterOunces: Int?

    // MARK: Activity metrics — fill only for ACTIVITY.
    @Guide(description: "Estimated minutes of active exercise/movement. Nil if not an activity insight.")
    var activeMinutes: Int?
    @Guide(description: "Estimated distance in miles for runs, walks, or rides. Nil if there was no distance.")
    var distanceMiles: Double?

    // MARK: Sleep metric — fill only for SLEEP.
    @Guide(description: "Estimated hours of sleep. Nil if this is not a sleep insight.")
    var sleepHours: Double?
}
