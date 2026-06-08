//
//  InsightCategory.swift
//  LYFESTYL
//
//  The four lifestyle categories the model breaks every entry into
//  (CLAUDE.md §1). Each maps to an SF Symbol and a Solarized accent so the Log
//  reads like Apple Health at a glance.
//

import SwiftUI

enum InsightCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case nutrition = "NUTRITION"
    case activity  = "ACTIVITY"
    case sleep     = "SLEEP"
    case health    = "HEALTH"

    var id: String { rawValue }

    /// ALL-CAPS label for headers (matches `rawValue`).
    var label: String { rawValue }

    /// SF Symbol — first-party, Apple-Health-flavored iconography.
    var symbolName: String {
        switch self {
        case .nutrition: "fork.knife"
        case .activity:  "figure.run"
        case .sleep:     "bed.double.fill"
        case .health:    "heart.fill"
        }
    }

    /// A distinct, on-palette accent per category (used for the icon chip and
    /// chart series). Kept off the rank colors so the two systems don't clash.
    var accent: Color {
        switch self {
        case .nutrition: Solar.green
        case .activity:  Solar.blue
        case .sleep:     Solar.violet
        case .health:    Solar.magenta
        }
    }

    /// Stable display order for sections/lists.
    var sortIndex: Int {
        switch self {
        case .nutrition: 0
        case .activity:  1
        case .sleep:     2
        case .health:    3
        }
    }

    /// Defensive parse from arbitrary model output (case-insensitive). Returns
    /// nil for unrecognized categories so callers can drop them cleanly.
    init?(modelValue raw: String) {
        let key = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = InsightCategory(rawValue: key) else { return nil }
        self = value
    }
}
