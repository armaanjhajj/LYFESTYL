//
//  MealLog.swift
//  LYFESTYL
//
//  Every write to the meal history goes through here, so the local store,
//  CloudKit (via SwiftData's mirroring) and Apple Health never disagree.
//

import Foundation
import OSLog
import SwiftData

struct MealLog {
    let context: ModelContext
    let health: HealthService

    /// False if the meal couldn't be saved, so the caller doesn't celebrate.
    @discardableResult
    func log(_ items: [FoodItem], at date: Date) -> Bool {
        let entry = MealEntry(loggedAt: date, items: items)
        context.insert(entry)
        guard save() else {
            context.delete(entry)
            return false
        }
        let id = entry.id, title = entry.title, nutrition = entry.nutrition
        Task { await health.save(mealID: id, at: date, title: title, nutrition: nutrition) }
        return true
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

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Self.logger.error("Saving meals failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static let logger = Logger(subsystem: "Moments.LYFESTYL", category: "MealLog")
}
