//
//  Metric.swift
//  LYFESTYL
//
//  The fixed set of tangible metrics the model estimates. Modeling these as a
//  closed enum (rather than free-form key/value pairs) is what makes trends
//  reliable — every "calories" point lands on the same series over time.
//

import SwiftUI

enum MetricKey: String, CaseIterable, Identifiable, Codable, Hashable {
    case calories
    case proteinGrams
    case carbsGrams
    case fatGrams
    case waterOunces
    case activeMinutes
    case distanceMiles
    case sleepHours

    var id: String { rawValue }

    /// Which category this metric belongs to (drives the trends picker grouping).
    var category: InsightCategory {
        switch self {
        case .calories, .proteinGrams, .carbsGrams, .fatGrams, .waterOunces: .nutrition
        case .activeMinutes, .distanceMiles: .activity
        case .sleepHours: .sleep
        }
    }

    /// Short label for the trends picker and axis.
    var label: String {
        switch self {
        case .calories:     "Calories"
        case .proteinGrams: "Protein"
        case .carbsGrams:   "Carbs"
        case .fatGrams:     "Fat"
        case .waterOunces:  "Water"
        case .activeMinutes:"Active Minutes"
        case .distanceMiles:"Distance"
        case .sleepHours:   "Sleep"
        }
    }

    /// Unit suffix used when rendering a value.
    var unit: String {
        switch self {
        case .calories:     "kcal"
        case .proteinGrams, .carbsGrams, .fatGrams: "g"
        case .waterOunces:  "oz"
        case .activeMinutes:"min"
        case .distanceMiles:"mi"
        case .sleepHours:   "h"
        }
    }

    var symbolName: String {
        switch self {
        case .calories:     "flame.fill"
        case .proteinGrams: "fish.fill"
        case .carbsGrams:   "carrot.fill"
        case .fatGrams:     "drop.fill"
        case .waterOunces:  "waterbottle.fill"
        case .activeMinutes:"timer"
        case .distanceMiles:"point.topleft.down.to.point.bottomright.curvepath.fill"
        case .sleepHours:   "moon.zzz.fill"
        }
    }

    /// How a day's worth of this metric is aggregated for trends.
    enum Aggregation { case sum, average }
    var aggregation: Aggregation {
        switch self {
        case .sleepHours: .average      // sleep is a level, not a tally
        default:          .sum          // calories/protein/minutes/distance accumulate
        }
    }

    /// Decimal places when formatting.
    var fractionDigits: Int {
        switch self {
        case .distanceMiles, .sleepHours: 1
        default: 0
        }
    }

    /// Format a numeric value with the right precision and unit.
    func format(_ value: Double, includeUnit: Bool = true) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return includeUnit ? "\(number) \(unit)" : number
    }
}
