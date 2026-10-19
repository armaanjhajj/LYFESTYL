//
//  MealLog.swift
//  LYFESTYL
//
//  Every write to the meal history goes through here, so the local store,
//  CloudKit (via SwiftData's mirroring) and Apple Health never disagree.
//

import Foundation
import SwiftData

struct MealLog {
    let context: ModelContext
    let health: HealthService

    func log(_ items: [FoodItem], at date: Date) {
        let entry = MealEntry(loggedAt: date, items: items)
        context.insert(entry)
        save()
        let id = entry.id, title = entry.title, nutrition = entry.nutrition
        Task { await health.save(mealID: id, at: date, title: title, nutrition: nutrition) }
    }

    func update(_ entry: MealEntry, items: [FoodItem], at date: Date) {
        guard !items.isEmpty else { return delete([entry]) }
        entry.items = items
        entry.loggedAt = date
        save()
        let id = entry.id, title = entry.title, nutrition = entry.nutrition
        Task { await health.save(mealID: id, at: date, title: title, nutrition: nutrition) }
    }

    func delete(_ entries: [MealEntry]) {
        let ids = entries.map(\.id)
        entries.forEach(context.delete)
        save()
        Task { await health.delete(mealIDs: ids) }
    }

    func deleteAll() {
        let all = (try? context.fetch(FetchDescriptor<MealEntry>())) ?? []
        delete(all)
    }

    private func save() {
        try? context.save()
    }
}
