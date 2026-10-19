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
    check(habits.first { $0.kind == .lowProtein }?.detail.contains("5 of the last 5 days") == true, "detail counts days")

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
}

MainActor.assumeIsolated { run() }
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
