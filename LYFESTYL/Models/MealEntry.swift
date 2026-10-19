//
//  MealEntry.swift
//  LYFESTYL
//
//  The only persisted record. SwiftData keeps it in a local store and mirrors it
//  to the user's CloudKit private database (record type `CD_MealEntry`), which
//  is the source of truth across their devices. No image is ever stored, only
//  the foods, as one small binary blob per meal.
//
//  CloudKit-backed SwiftData rules: every attribute has a default, nothing is
//  unique, no required relationships.
//

import Foundation
import SwiftData

@Model
final class MealEntry {
    /// Stable across devices. Also the Apple Health sync identifier prefix, so an
    /// edit or delete on any device can find the samples this meal wrote.
    var id: UUID = UUID()
    var loggedAt: Date = Date.now
    /// `[FoodItem]` as a binary plist. See `FoodItem: Codable`.
    var itemsData: Data = Data()

    init(id: UUID = UUID(), loggedAt: Date = .now, items: [FoodItem]) {
        self.id = id
        self.loggedAt = loggedAt
        self.itemsData = items.encoded()
    }

    var items: [FoodItem] {
        get { [FoodItem](decoding: itemsData) }
        set { itemsData = newValue.encoded() }
    }

    var nutrition: Nutrition { items.nutrition }
    var title: String { items.title }
}
