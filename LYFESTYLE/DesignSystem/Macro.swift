//
//  Macro.swift
//  LYFESTYL
//
//  The four numbers the app tracks. Each one owns its label, unit, symbol and
//  accent so every ring, bar, chart series and row reads the same way.
//

import SwiftUI

nonisolated enum Macro: String, CaseIterable, Identifiable, Hashable, Sendable {
    case calories, protein, carbs, fat

    var id: String { rawValue }

    /// ALL-CAPS label for headers and chart legends.
    var label: String {
        switch self {
        case .calories: "CALORIES"
        case .protein:  "PROTEIN"
        case .carbs:    "CARBS"
        case .fat:      "FAT"
        }
    }

    /// Sentence-case name for body text ("Protein has been low").
    var name: String {
        switch self {
        case .calories: "Calories"
        case .protein:  "Protein"
        case .carbs:    "Carbs"
        case .fat:      "Fat"
        }
    }

    var unit: String { self == .calories ? "cal" : "g" }

    var symbol: String {
        switch self {
        case .calories: "flame.fill"
        case .protein:  "fish.fill"
        case .carbs:    "carrot.fill"
        case .fat:      "drop.fill"
        }
    }

    var accent: Color {
        switch self {
        case .calories: Solar.green
        case .protein:  Solar.blue
        case .carbs:    Solar.yellow
        case .fat:      Solar.magenta
        }
    }
}
