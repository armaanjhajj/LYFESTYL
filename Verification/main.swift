//
//  Verification/main.swift
//  LYFESTYL
//
//  Checks the app's pure logic against hand-worked expectations. Compiled
//  together with the real app sources by run.sh, so it tests the shipped code.
//

import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition { print("  ok   \(message)") } else { failures += 1; print("  FAIL \(message) (line \(line))") }
}
func food(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, servings: Double = 1) -> FoodItem {
    FoodItem(name: name, portion: "1 serving", servings: servings, base: Nutrition(calories: kcal, protein: p, carbs: c, fat: f))
}

@MainActor func run() {
    print("Storage")
    let meal = [food("Grilled chicken breast", 187, 35, 0, 4), food("White rice", 205, 4, 45, 0, servings: 1.5), food("Broccoli", 55, 4, 11, 1)]
    let data = meal.encoded()
    let decoded = [FoodItem](decoding: data)
    check(decoded.count == 3, "round trip keeps every item")
    check(decoded.map(\.name) == meal.map(\.name), "round trip keeps names in order")
    check(decoded[1].servings == 1.5 && decoded[0].servings == 1, "servings stored only when not 1, restored either way")
    check(decoded.nutrition == meal.nutrition, "round trip keeps nutrition")
    check(data.count < 100 * meal.count, "three foods encode to \(data.count) bytes (under 100 per item)")
    check([FoodItem](decoding: Data("junk".utf8)).isEmpty, "corrupt data decodes to empty, not a crash")
    check(meal.title == "Grilled chicken breast, White rice + 1 more", "meal title")

    print("Nutrition")
    let rice = meal[1].nutrition
    check(rice.calories == 307.5 && rice.carbs == 67.5, "servings scale nutrition")
    check(meal.nutrition.calories == 187 + 307.5 + 55, "meal total")

    print("Goals")
    let profile = BodyProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, aim: .maintain)
    // Mifflin-St Jeor: 10*80 + 6.25*180 - 5*30 + 5 = 1780; x1.55 = 2759
    check(abs(profile.restingCalories - 1780) < 0.01, "resting calories 1780")
    let g = profile.suggestedGoals
    check(g.calories == 2760, "maintenance rounds to 2760, got \(g.calories)")
    check(g.protein == 128, "protein 1.6 g/kg = 128, got \(g.protein)")
    check(abs(g.protein * 4 + g.carbs * 4 + g.fat * 9 - g.calories) < 15, "macros add back up to calories")
    let small = BodyProfile(sex: .female, age: 70, heightCm: 150, weightKg: 45, activity: .sedentary, aim: .lose)
    check(small.suggestedGoals.calories >= 1200, "calorie floor holds, got \(small.suggestedGoals.calories)")

    print("Habits")
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
    let goals = Goals(calories: 2000, protein: 140, carbs: 220, fat: 65)
    func day(_ back: Int, hour: Int = 12) -> Date { cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now))!.addingTimeInterval(Double(hour) * 3600) }

    let twoDays = HabitEngine.dailyTotals([(day(1), Nutrition(calories: 2000, protein: 50, carbs: 200, fat: 60)), (day(2), Nutrition(calories: 2000, protein: 50, carbs: 200, fat: 60))], calendar: cal)
    check(HabitEngine.evaluate(days: twoDays, goals: goals, now: now, calendar: cal) == .notEnoughData(loggedDays: 2), "two logged days is not a pattern")

    var meals: [(date: Date, nutrition: Nutrition)] = []
    for back in 1...5 {
        meals.append((day(back, hour: 8), Nutrition(calories: 900, protein: 30, carbs: 150, fat: 25)))
        meals.append((day(back, hour: 19), Nutrition(calories: 1200, protein: 40, carbs: 160, fat: 40)))
    }
    meals.append((day(0), Nutrition(calories: 5000, protein: 0, carbs: 900, fat: 200))) // today: ignored
    meals.append((day(9), Nutrition(calories: 9000, protein: 0, carbs: 900, fat: 200))) // outside window
    let days = HabitEngine.dailyTotals(meals, calendar: cal)
    check(days.first?.mealCount == 1 && days.count == 7, "meals group into calendar days")
    guard case .habits(let habits) = HabitEngine.evaluate(days: days, goals: goals, now: now, calendar: cal) else {
        check(false, "five logged days should produce habits"); return
    }
    let kinds = Set(habits.map(\.kind))
    check(kinds.contains(.lowProtein), "70 g vs 140 g goal flags low protein")
    check(kinds.contains(.highCarbs), "310 g vs 220 g goal flags high carbs")
    check(!kinds.contains(.highFat), "65 g fat on a 65 g goal is not flagged")
    check(!kinds.contains(.highCalories) && !kinds.contains(.lowCalories), "2100 kcal on 2000 is within range")
    check(habits.first { $0.kind == .lowProtein }?.detail.contains("5 of 5 days") == true, "detail counts days")

    let steady = HabitEngine.dailyTotals((1...4).map { (day($0), Nutrition(calories: 2000, protein: 140, carbs: 220, fat: 65)) }, calendar: cal)
    if case .habits(let h) = HabitEngine.evaluate(days: steady, goals: goals, now: now, calendar: cal) {
        check(h.map(\.kind) == [.onTrack], "on-goal days produce only the on-track note")
    } else { check(false, "steady days should evaluate") }

    print("Export")
    let csv = MealExport(rows: [(day(1, hour: 13), [food("Chicken, \"spicy\"", 300, 30, 10, 12)])]).csv
    let lines = csv.split(separator: "\n")
    check(lines.count == 2, "header plus one row")
    check(lines[1].contains("\"Chicken, \"\"spicy\"\"\""), "commas and quotes are escaped")
    check(lines[1].hasSuffix(",300,30,10,12"), "numbers are whole and in column order")

    print("Search")
    check(!CommonFoods.search("rice").isEmpty, "rice finds results")
    check(CommonFoods.search("chicken breast").allSatisfy { $0.name.lowercased().contains("chicken") && $0.name.lowercased().contains("breast") }, "every word must match")
    check(CommonFoods.search("   ").isEmpty, "blank query finds nothing")
    // Alcohol (7 kcal/g) isn't a macro here, and fiber-heavy vegetables count
    // carbs that mostly aren't absorbed, so those get a looser check.
    let bad = CommonFoods.all.filter { f in
        let name = f.name.lowercased()
        guard !name.contains("beer"), !name.contains("wine") else { return false }
        let fromMacros = f.base.protein * 4 + f.base.carbs * 4 + f.base.fat * 9
        return f.base.calories > 40 && abs(fromMacros - f.base.calories) / f.base.calories > 0.3
    }
    check(bad.isEmpty, "bundled foods' macros agree with their calories within 30% (alcohol excluded)" + (bad.isEmpty ? "" : ": " + bad.map(\.name).joined(separator: ", ")))

    print("Labels")
    let front = LabelFacts(lines: ["fairlife", "nutrition plan", "30g", "HIGH QUALITY", "PROTEIN", "2g", "SUGAR", "150", "CALORIES", "CHOCOLATE", "NUTRITION SHAKE"])
    check(front.protein == 30, "front of pack: 30g HIGH QUALITY PROTEIN is 30 g, got \(String(describing: front.protein))")
    check(front.calories == 150, "front of pack: 150 CALORIES, got \(String(describing: front.calories))")
    check(front.carbs == nil && front.fat == nil, "front of pack: sugar is not carbs, no fat claimed")

    let panel = LabelFacts(lines: ["Nutrition Facts", "1 serving per container", "Serving size 1 bottle (340mL)", "Amount per serving", "Calories 150",
                                   "% Daily Value*", "Total Fat 2.5g 3%", "Saturated Fat 1.5g 8%", "Trans Fat 0g", "Cholesterol 20mg 7%",
                                   "Sodium 280mg 12%", "Total Carbohydrate 4g 1%", "Dietary Fiber 1g 4%", "Total Sugars 2g", "Protein 30g 60%",
                                   "*The % Daily Value tells you how much a nutrient contributes to a daily diet. 2,000 calories a day is used for general nutrition advice."])
    check(panel.calories == 150 && panel.protein == 30, "panel: calories and protein")
    check(panel.fat == 2.5, "panel: total fat, not saturated, got \(String(describing: panel.fat))")
    check(panel.carbs == 4, "panel: total carbohydrate, got \(String(describing: panel.carbs))")
    check(panel.servingSize == "1 bottle (340ml)", "panel: serving size, got \(String(describing: panel.servingSize))")

    let split = LabelFacts(lines: ["Calories", "230", "Total Fat", "8g", "Saturated Fat 1g", "Total Carbohydrate", "37g", "Protein", "3g"])
    check(split.calories == 230 && split.fat == 8 && split.carbs == 37 && split.protein == 3, "panel with values on their own lines")

    let multipack = LabelFacts(lines: ["nutrition plan", "150", "CALORIES", "PER BOTTLE", "8", "BOTTLES"])
    check(multipack.calories == 150, "150 CALORIES PER BOTTLE 8 is 150, got \(String(describing: multipack.calories))")
    let misread = LabelFacts(lines: ["CORE", "POWER", "26.", "HIGH QUALITY", "PROTEIN", "14 FL OZ (414 mL)"])
    check(misread.protein == 26, "OCR reading 26g as 26. still finds the protein, got \(String(describing: misread.protein))")

    // Lines exactly as Vision read the user's own photo of a Fairlife panel.
    let realPanel = LabelFacts(lines: ["SHAKE WELL", "Nutrition Facts", "serving per container", "Serving size 1 Bottle (340mL)", "mount per serving",
                                       "Calories", "150", "% Daily Value*", "Total Fat 2.5g", "3%", "Saturated Fat 1.5g", "8%", "Trans Fat 0g",
                                       "Cholesterol 25mg", "8%", "Sodium 230mg", "10%", "drate 4g.", "196", "Dietary Fiber 1g", "4%",
                                       "Total Sugars 2g", "Includes 0g Added Sugars", "0%", "Proteln 30g", "60%"])
    check(realPanel.calories == 150 && realPanel.fat == 2.5, "real panel: calories and fat")
    check(realPanel.protein == 30, "real panel: \"Proteln 30g\" is protein, got \(String(describing: realPanel.protein))")
    check(realPanel.carbs == 4, "real panel: clipped \"drate 4g\" is carbs, got \(String(describing: realPanel.carbs))")
    check(realPanel.servingSize == "1 bottle (340ml)", "real panel: serving size stops at the parenthesis, got \(String(describing: realPanel.servingSize))")

    let bottle = DraftItem(food: food("Fairlife Nutrition Plan", 150, 30, 0, 3), confidence: .high)
    let flavor = DraftItem(food: food("chocolate", 150, 0, 0, 0), confidence: .low)
    let frontLines = ["farlife", "nutrition plan", "2g SUGAR", "150 CALORIES", "CHOCOLATE", "NUTRITION SHAKE"]
    let cleaned = LabelFacts.removeLabelWords(from: [C(item: bottle, isPackaged: true), C(item: flavor, isPackaged: false)], labelLines: frontLines)
    check(cleaned.map(\.item) == [bottle], "a flavor printed on the label is not a separate food")
    let unflagged = LabelFacts.removeLabelWords(from: [C(item: bottle, isPackaged: false), C(item: flavor, isPackaged: false)], labelLines: frontLines)
    check(unflagged.map(\.item) == [bottle], "with nothing marked packaged, the best label match is the product")
    let banana = DraftItem(food: food("Banana", 105, 1, 27, 0), confidence: .high)
    check(LabelFacts.removeLabelWords(from: [C(item: bottle, isPackaged: true), C(item: banana, isPackaged: false)], labelLines: frontLines).count == 2, "a real second food stays")

    let footnoteOnly = LabelFacts(lines: ["Percent Daily Values are based on a 2,000 calorie diet."])
    check(footnoteOnly.isEmpty, "a 2,000 calorie diet footnote is not a calorie count")
    check(LabelFacts(lines: ["Table 4", "Thank you"]).isEmpty, "unrelated text has no facts")

    let guess = DraftItem(food: food("Protein shake", 250, 20, 10, 8), confidence: .medium)
    let plate = DraftItem(food: food("Rice", 205, 4, 45, 0), confidence: .high)
    typealias C = LabelFacts.Candidate
    let applied = LabelFacts.apply(front, to: [C(item: guess, isPackaged: true), C(item: plate, isPackaged: false)], labelLines: [])
    check(applied[0].food.base.protein == 30 && applied[0].food.base.calories == 150, "label numbers replace the packaged item's guess")
    check(applied[0].food.base.carbs == 10, "numbers the label doesn't state keep the estimate")
    check(applied[0].confidence == .high, "a read label is high confidence")
    check(applied[1] == plate, "other foods are untouched")
    check(LabelFacts.apply(front, to: [C(item: guess, isPackaged: false), C(item: plate, isPackaged: false)], labelLines: []) == [guess, plate], "with several foods and no packaged one, nothing is overridden")
    check(LabelFacts.apply(front, to: [C(item: guess, isPackaged: false)], labelLines: [])[0].food.base.protein == 30, "a lone item takes the label")

    // The user's desk: a Fairlife bottle in front of a Dunkin cup, both branded.
    let shake = C(item: guess, isPackaged: true, product: "fairlife nutrition plan")
    let dunkin = C(item: DraftItem(food: food("Iced coffee", 120, 0, 0, 0), confidence: .low), isPackaged: true, product: "Dunkin iced coffee")
    let deskLines = ["DUNKIN", "farlife", "nutrition plan", "HIGH QUALITY", "PROTEIN", "150 CALORIES", "CHOCOLATE"]
    check(LabelFacts.labelOwner(in: [dunkin, shake], labelLines: deskLines) == 1, "with two branded items, the label goes to the one its text matches")
    let desk = LabelFacts.apply(front, to: [dunkin, shake], labelLines: deskLines)
    check(desk[1].food.base.calories == 150 && desk[0].food.base.calories == 120, "only the matched product takes the label numbers")

    print("Names")
    check(ScannedFood.plainName("protein shake") == "Protein Shake", "lowercase names are title-cased")
    check(ScannedFood.plainName("Chicken salad 2 cups") == "Chicken salad", "numbers are dropped from names")
    check(ScannedFood.plainName("Grilled chicken breast with lemon herbs") == "Grilled chicken breast with", "names are capped at four words")
    check(ScannedFood.plainName("300") == "Food", "a name of only numbers falls back to Food")
}

MainActor.assumeIsolated { run() }
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
