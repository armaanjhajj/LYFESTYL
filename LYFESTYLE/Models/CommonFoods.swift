//
//  CommonFoods.swift
//  LYFESTYL
//
//  A small bundled table of everyday foods, so search returns something useful
//  instantly, offline, and on iPhones without Apple Intelligence. Values are
//  rounded from USDA FoodData Central (or typical chain-restaurant labels for
//  restaurant items) for the stated portion: kcal, protein g, carbs g, fat g.
//

import Foundation

nonisolated enum CommonFoods {

    static let all: [FoodItem] = rows.map { name, portion, kcal, p, c, f in
        FoodItem(name: name, portion: portion, base: Nutrition(calories: kcal, protein: p, carbs: c, fat: f))
    }

    /// Foods whose name contains every word of the query, best match first.
    static func search(_ query: String, limit: Int = 12) -> [FoodItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let matches = all.filter { food in
            let name = food.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
        let first = words[0]
        return matches
            .sorted { a, b in
                let ap = a.name.lowercased().hasPrefix(first), bp = b.name.lowercased().hasPrefix(first)
                return ap != bp ? ap : a.name.count < b.name.count
            }
            .prefix(limit)
            .map { $0 }
    }

    private static let rows: [(String, String, Double, Double, Double, Double)] = [
        // Protein
        ("Chicken breast, grilled", "4 oz", 187, 35, 0, 4),
        ("Chicken thigh, roasted", "4 oz", 236, 29, 0, 12),
        ("Fried chicken breast", "1 piece", 390, 39, 11, 21),
        ("Chicken nuggets", "6 pieces", 250, 14, 15, 15),
        ("Ground beef, 85% lean", "3 oz cooked", 213, 22, 0, 13),
        ("Steak, sirloin", "6 oz", 340, 51, 0, 14),
        ("Pork chop", "4 oz", 230, 33, 0, 10),
        ("Bacon", "3 slices", 129, 9, 0, 10),
        ("Turkey, deli sliced", "2 oz", 60, 12, 2, 1),
        ("Salmon, baked", "6 oz", 350, 37, 0, 21),
        ("Tuna, canned in water", "1 can, drained", 130, 29, 0, 1),
        ("Shrimp, cooked", "4 oz", 112, 27, 0, 0),
        ("Tofu, firm", "3 oz", 90, 9, 2, 5),
        ("Egg", "1 large", 72, 6, 0, 5),
        ("Scrambled eggs", "2 eggs", 200, 13, 2, 15),
        ("Egg whites", "1/2 cup", 63, 13, 1, 0),
        ("Black beans", "1/2 cup", 114, 8, 20, 0),
        ("Lentils, cooked", "1 cup", 230, 18, 40, 1),
        ("Protein shake, whey with water", "1 scoop", 120, 24, 3, 2),
        ("Protein bar", "1 bar", 200, 20, 22, 7),

        // Dairy
        ("Milk, 2%", "1 cup", 122, 8, 12, 5),
        ("Milk, whole", "1 cup", 149, 8, 12, 8),
        ("Greek yogurt, plain nonfat", "1 container (170 g)", 100, 17, 6, 0),
        ("Yogurt, flavored", "1 container (150 g)", 140, 5, 25, 2),
        ("Cottage cheese", "1/2 cup", 111, 13, 4, 5),
        ("Cheddar cheese", "1 oz", 114, 7, 0, 9),
        ("Mozzarella cheese", "1 oz", 85, 6, 1, 6),
        ("Cream cheese", "2 tbsp", 100, 2, 2, 10),
        ("Butter", "1 tbsp", 102, 0, 0, 12),
        ("Ice cream, vanilla", "1/2 cup", 137, 2, 16, 7),

        // Grains and breakfast
        ("White rice, cooked", "1 cup", 205, 4, 45, 0),
        ("Brown rice, cooked", "1 cup", 218, 5, 46, 2),
        ("Fried rice", "1 cup", 240, 6, 34, 9),
        ("Quinoa, cooked", "1 cup", 222, 8, 39, 4),
        ("Pasta, cooked", "1 cup", 220, 8, 43, 1),
        ("Bread, white", "1 slice", 75, 2, 14, 1),
        ("Bread, whole wheat", "1 slice", 80, 4, 14, 1),
        ("Bagel, plain", "1 medium", 277, 11, 55, 1),
        ("Croissant", "1 medium", 231, 5, 26, 12),
        ("Blueberry muffin", "1 large", 420, 6, 58, 19),
        ("Glazed donut", "1 donut", 255, 4, 30, 14),
        ("Oatmeal, cooked", "1 cup", 166, 6, 28, 4),
        ("Granola", "1/2 cup", 290, 7, 33, 14),
        ("Cereal with milk", "1 bowl", 180, 6, 30, 3),
        ("Pancakes", "3 pancakes (4 in)", 260, 7, 33, 11),
        ("Waffle", "1 waffle (7 in)", 218, 6, 25, 11),
        ("French toast", "2 slices", 300, 10, 32, 14),
        ("Maple syrup", "2 tbsp", 104, 0, 27, 0),
        ("Flour tortilla", "1 tortilla (8 in)", 146, 4, 25, 4),
        ("Corn tortilla", "1 tortilla", 52, 1, 11, 1),

        // Fruit
        ("Apple", "1 medium", 95, 0, 25, 0),
        ("Banana", "1 medium", 105, 1, 27, 0),
        ("Orange", "1 medium", 62, 1, 15, 0),
        ("Strawberries", "1 cup", 49, 1, 12, 0),
        ("Blueberries", "1 cup", 84, 1, 21, 0),
        ("Grapes", "1 cup", 104, 1, 27, 0),
        ("Watermelon", "1 cup diced", 46, 1, 12, 0),
        ("Mango", "1 cup", 99, 1, 25, 1),
        ("Pineapple", "1 cup", 82, 1, 22, 0),
        ("Avocado", "1/2 avocado", 161, 2, 9, 15),

        // Vegetables and sides
        ("Broccoli, steamed", "1 cup", 55, 4, 11, 1),
        ("Green beans", "1 cup", 44, 2, 10, 0),
        ("Baby carrots", "10 carrots", 35, 1, 8, 0),
        ("Corn on the cob", "1 ear", 90, 3, 19, 1),
        ("Green salad, no dressing", "2 cups", 20, 2, 4, 0),
        ("Caesar salad", "1 side", 200, 5, 9, 16),
        ("Salad with grilled chicken", "1 bowl, dressed", 450, 38, 15, 26),
        ("Baked potato", "1 medium", 161, 4, 37, 0),
        ("Sweet potato, baked", "1 medium", 103, 2, 24, 0),
        ("Mashed potatoes", "1 cup", 237, 4, 35, 9),
        ("French fries", "1 medium order", 340, 4, 44, 16),

        // Meals
        ("Cheeseburger, fast food", "1 burger", 300, 15, 32, 13),
        ("Cheeseburger, restaurant", "1 burger", 800, 42, 46, 48),
        ("Hot dog with bun", "1 hot dog", 280, 10, 24, 15),
        ("Pizza, cheese", "1 slice (14 in)", 285, 12, 36, 10),
        ("Pizza, pepperoni", "1 slice (14 in)", 313, 13, 36, 13),
        ("Chicken burrito", "1 large", 1070, 60, 120, 39),
        ("Taco, beef", "1 taco", 170, 8, 13, 9),
        ("Turkey sandwich", "1 sandwich", 420, 28, 32, 19),
        ("Grilled cheese", "1 sandwich", 480, 17, 28, 33),
        ("Peanut butter and jelly sandwich", "1 sandwich", 390, 12, 48, 18),
        ("Spaghetti with marinara", "2 cups", 510, 18, 96, 6),
        ("Mac and cheese", "1 cup", 380, 14, 48, 15),
        ("Lasagna", "1 piece", 400, 24, 37, 17),
        ("Chili with beans", "1 cup", 260, 20, 22, 10),
        ("Chicken noodle soup", "1 cup", 80, 6, 9, 2),
        ("Chicken curry with rice", "1 plate", 690, 35, 75, 28),
        ("Pad thai", "1 plate", 790, 30, 100, 30),
        ("Ramen, restaurant", "1 bowl", 800, 35, 85, 35),
        ("Instant ramen", "1 package", 380, 9, 52, 14),
        ("California roll", "8 pieces", 255, 9, 38, 7),
        ("Salmon nigiri", "2 pieces", 140, 8, 20, 3),
        ("Poke bowl", "1 bowl", 615, 35, 80, 17),

        // Snacks and sweets
        ("Almonds", "1 oz", 164, 6, 6, 14),
        ("Mixed nuts", "1 oz", 170, 5, 6, 15),
        ("Peanut butter", "2 tbsp", 190, 7, 7, 16),
        ("Hummus", "2 tbsp", 70, 2, 4, 5),
        ("Potato chips", "1 oz", 155, 2, 15, 10),
        ("Popcorn, air-popped", "3 cups", 93, 3, 19, 1),
        ("Dark chocolate", "1 oz", 170, 2, 13, 12),
        ("Chocolate chip cookie", "1 large", 230, 3, 30, 11),
        ("Brownie", "1 piece", 240, 3, 36, 10),

        // Drinks
        ("Coffee, black", "1 cup", 2, 0, 0, 0),
        ("Latte, 2% milk", "16 oz", 190, 13, 19, 7),
        ("Cappuccino, 2% milk", "16 oz", 140, 9, 14, 5),
        ("Orange juice", "1 cup", 112, 2, 26, 0),
        ("Fruit smoothie", "16 oz", 285, 4, 65, 1),
        ("Bubble tea", "16 oz", 350, 2, 70, 7),
        ("Cola", "12 oz can", 140, 0, 39, 0),
        ("Sports drink", "20 oz", 140, 0, 36, 0),
        ("Beer", "12 oz", 153, 2, 13, 0),
        ("Light beer", "12 oz", 103, 1, 6, 0),
        ("Wine, red", "5 oz", 125, 0, 4, 0),
        ("Wine, white", "5 oz", 121, 0, 4, 0),

        // Extras
        ("Olive oil", "1 tbsp", 119, 0, 0, 14),
        ("Mayonnaise", "1 tbsp", 94, 0, 0, 10),
        ("Ranch dressing", "2 tbsp", 130, 0, 2, 13),
        ("Vinaigrette", "2 tbsp", 90, 0, 3, 9),
        ("Ketchup", "1 tbsp", 20, 0, 5, 0),
        ("Salsa", "2 tbsp", 10, 0, 2, 0),
        ("Guacamole", "1/4 cup", 100, 1, 5, 9),
        ("Sour cream", "2 tbsp", 57, 1, 1, 6),
        ("Honey", "1 tbsp", 64, 0, 17, 0),
        ("Sugar", "1 tsp", 16, 0, 4, 0),
    ]
}
