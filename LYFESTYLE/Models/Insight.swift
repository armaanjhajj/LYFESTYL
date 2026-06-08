//
//  Insight.swift
//  LYFESTYL
//
//  The structured, trackable breakdown of one category within one entry — the
//  app/cache representation (clean camelCase). Built from the model's
//  `CategoryInsight`. Supabase row mapping lives in SupabaseService (DTOs).
//

import Foundation

struct Insight: Identifiable, Codable, Hashable {
    var id: UUID
    var entryID: UUID
    var category: InsightCategory
    var rank: Rank
    var title: String
    var detail: String

    // Tangible estimates — only the ones relevant to `category` are populated.
    var calories: Int?
    var proteinGrams: Int?
    var carbsGrams: Int?
    var fatGrams: Int?
    var waterOunces: Int?
    var activeMinutes: Int?
    var distanceMiles: Double?
    var sleepHours: Double?

    var createdAt: Date
    var entryDate: Date

    init(
        id: UUID = UUID(),
        entryID: UUID,
        category: InsightCategory,
        rank: Rank,
        title: String,
        detail: String,
        calories: Int? = nil,
        proteinGrams: Int? = nil,
        carbsGrams: Int? = nil,
        fatGrams: Int? = nil,
        waterOunces: Int? = nil,
        activeMinutes: Int? = nil,
        distanceMiles: Double? = nil,
        sleepHours: Double? = nil,
        createdAt: Date,
        entryDate: Date
    ) {
        self.id = id
        self.entryID = entryID
        self.category = category
        self.rank = rank
        self.title = title
        self.detail = detail
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.waterOunces = waterOunces
        self.activeMinutes = activeMinutes
        self.distanceMiles = distanceMiles
        self.sleepHours = sleepHours
        self.createdAt = createdAt
        self.entryDate = entryDate
    }
}

extension Insight {
    /// Numeric value for a given metric, if present.
    func value(for key: MetricKey) -> Double? {
        switch key {
        case .calories:     calories.map(Double.init)
        case .proteinGrams: proteinGrams.map(Double.init)
        case .carbsGrams:   carbsGrams.map(Double.init)
        case .fatGrams:     fatGrams.map(Double.init)
        case .waterOunces:  waterOunces.map(Double.init)
        case .activeMinutes:activeMinutes.map(Double.init)
        case .distanceMiles:distanceMiles
        case .sleepHours:   sleepHours
        }
    }

    /// Ordered, present metrics for this insight, ready to render as pills.
    var displayMetrics: [(key: MetricKey, text: String)] {
        let order: [MetricKey]
        switch category {
        case .nutrition: order = [.calories, .proteinGrams, .carbsGrams, .fatGrams, .waterOunces]
        case .activity:  order = [.activeMinutes, .distanceMiles]
        case .sleep:     order = [.sleepHours]
        case .health:    order = []
        }
        return order.compactMap { key in
            guard let v = value(for: key) else { return nil }
            return (key, key.format(v))
        }
    }

    /// Build a cache/domain `Insight` from a model `CategoryInsight`. Returns nil
    /// if the category is unrecognized (defensive — never crash on odd output).
    init?(from ci: CategoryInsight, entryID: UUID, entryDate: Date, createdAt: Date) {
        guard let category = InsightCategory(modelValue: ci.category) else { return nil }
        // Only keep metrics that belong to this category, so a stray field on the
        // wrong category never pollutes a trend.
        let isNutrition = category == .nutrition
        let isActivity  = category == .activity
        let isSleep     = category == .sleep
        self.init(
            entryID: entryID,
            category: category,
            rank: Rank(modelValue: ci.rank),
            title: ci.title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: ci.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: isNutrition ? ci.calories.flatMap(Self.sane) : nil,
            proteinGrams: isNutrition ? ci.proteinGrams.flatMap(Self.sane) : nil,
            carbsGrams: isNutrition ? ci.carbsGrams.flatMap(Self.sane) : nil,
            fatGrams: isNutrition ? ci.fatGrams.flatMap(Self.sane) : nil,
            waterOunces: isNutrition ? ci.waterOunces.flatMap(Self.sane) : nil,
            activeMinutes: isActivity ? ci.activeMinutes.flatMap(Self.sane) : nil,
            distanceMiles: isActivity ? ci.distanceMiles.flatMap(Self.saneDouble) : nil,
            sleepHours: isSleep ? ci.sleepHours.flatMap(Self.saneDouble) : nil,
            createdAt: createdAt,
            entryDate: entryDate
        )
    }

    /// Clamp obviously-bogus integer estimates (negatives / absurd highs).
    private static func sane(_ v: Int) -> Int? {
        guard v >= 0, v <= 100_000 else { return nil }
        return v
    }
    private static func saneDouble(_ v: Double) -> Double? {
        guard v.isFinite, v >= 0, v <= 100_000 else { return nil }
        return v
    }
}
