//
//  Rank.swift
//  LYFESTYL
//
//  The proprietary 5-point qualitative scale (CLAUDE.md §1, §3.1). The on-device
//  model emits one of these as a String; we map it to a typed value, a numeric
//  score for trend math, and a Solarized accent color — in exactly one place.
//

import SwiftUI

enum Rank: String, CaseIterable, Codable, Hashable, Identifiable {
    case excellent = "EXCELLENT"
    case good      = "GOOD"
    case okay      = "OKAY"
    case bad       = "BAD"
    case awful     = "AWFUL"

    var id: String { rawValue }

    /// ALL-CAPS label for display (matches `rawValue`).
    var label: String { rawValue }

    /// Numeric score 5 (EXCELLENT) … 1 (AWFUL) for averaging / charting.
    var score: Int {
        switch self {
        case .excellent: 5
        case .good:      4
        case .okay:      3
        case .bad:       2
        case .awful:     1
        }
    }

    /// Palette mapping per CLAUDE.md §3.1: EXCELLENT→green, GOOD→cyan,
    /// OKAY→yellow, BAD→orange, AWFUL→red.
    var color: Color {
        switch self {
        case .excellent: Solar.green
        case .good:      Solar.cyan
        case .okay:      Solar.yellow
        case .bad:       Solar.orange
        case .awful:     Solar.red
        }
    }

    /// SF Symbol that reads at a glance next to the label.
    var symbolName: String {
        switch self {
        case .excellent: "checkmark.seal.fill"
        case .good:      "checkmark.circle.fill"
        case .okay:      "minus.circle.fill"
        case .bad:       "exclamationmark.triangle.fill"
        case .awful:     "xmark.octagon.fill"
        }
    }

    /// Defensive parse from arbitrary model output (case-insensitive). Falls
    /// back to `.okay` so a stray value never crashes or drops an insight.
    init(modelValue raw: String) {
        self = Rank(rawValue: raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)) ?? .okay
    }

    /// Build a rank from an averaged score (used by trend summaries).
    init(roundedScore value: Double) {
        switch value.rounded() {
        case ..<1.5: self = .awful
        case ..<2.5: self = .bad
        case ..<3.5: self = .okay
        case ..<4.5: self = .good
        default:     self = .excellent
        }
    }
}
