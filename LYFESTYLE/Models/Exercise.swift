//
//  Exercise.swift
//  LYFESTYL
//
//  The vocabulary for the workout tracker (the ACTIVITY surface). Every logged
//  movement resolves to one `Exercise` in `ExerciseLibrary`, and each exercise
//  declares the muscles it works: up to two PRIMARY movers and up to two
//  ACCESSORY muscles (four total, per the product spec). Those mappings are the
//  single source of truth that powers the STYL muscle-balance read and the
//  on-device workout suggestions, so they live in code, not in the database.
//
//  Neutral by design (CLAUDE.md / quiet-AI direction): this only describes what a
//  movement trains. It never scores the user or estimates calories.
//

import SwiftUI

// MARK: - Body system (the coarse region the user reasons about)

/// The high-level trainable regions surfaced in STYL: "am I doing enough cardio,
/// arms, core?" Every `MuscleGroup` rolls up into exactly one of these.
nonisolated enum BodySystem: String, CaseIterable, Codable, Hashable, Identifiable {
    case chest, back, shoulders, arms, legs, core, cardio

    var id: String { rawValue }

    /// ALL-CAPS label (matches the app's header treatment).
    var label: String { rawValue.uppercased() }

    /// SF Symbol, first-party iconography.
    var symbolName: String {
        switch self {
        case .chest:     "figure.strengthtraining.traditional"
        case .back:      "figure.strengthtraining.functional"
        case .shoulders: "figure.arms.open"
        case .arms:      "dumbbell.fill"
        case .legs:      "figure.walk"
        case .core:      "figure.core.training"
        case .cardio:    "heart.fill"
        }
    }

    /// On-palette accent (Solarized only, never a raw system color).
    var accent: Color {
        switch self {
        case .chest:     Solar.blue
        case .back:      Solar.cyan
        case .shoulders: Solar.violet
        case .arms:      Solar.green
        case .legs:      Solar.yellow
        case .core:      Solar.orange
        case .cardio:    Solar.magenta
        }
    }

    /// Stable display order.
    var sortIndex: Int {
        switch self {
        case .chest: 0
        case .back: 1
        case .shoulders: 2
        case .arms: 3
        case .legs: 4
        case .core: 5
        case .cardio: 6
        }
    }
}

// MARK: - Muscle group (the fine-grained mover)

/// The specific muscles an exercise can train. Kept practical, the set a lifter
/// actually programs around, not an anatomy textbook. Each rolls up to a
/// `BodySystem`.
nonisolated enum MuscleGroup: String, CaseIterable, Codable, Hashable, Identifiable {
    // Chest
    case chest
    // Back
    case lats, upperBack, traps, lowerBack
    // Shoulders
    case frontDelts, sideDelts, rearDelts
    // Arms
    case biceps, triceps, forearms
    // Legs
    case quads, hamstrings, glutes, calves, adductors, abductors
    // Core
    case abs, obliques
    // Cardio (heart / lungs / conditioning)
    case cardio

    var id: String { rawValue }

    /// Short human label for chips and the muscle map.
    var label: String {
        switch self {
        case .chest:      "Chest"
        case .lats:       "Lats"
        case .upperBack:  "Upper Back"
        case .traps:      "Traps"
        case .lowerBack:  "Lower Back"
        case .frontDelts: "Front Delts"
        case .sideDelts:  "Side Delts"
        case .rearDelts:  "Rear Delts"
        case .biceps:     "Biceps"
        case .triceps:    "Triceps"
        case .forearms:   "Forearms"
        case .quads:      "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes:     "Glutes"
        case .calves:     "Calves"
        case .adductors:  "Adductors"
        case .abductors:  "Abductors"
        case .abs:        "Abs"
        case .obliques:   "Obliques"
        case .cardio:     "Cardio"
        }
    }

    /// The region this muscle belongs to.
    var system: BodySystem {
        switch self {
        case .chest:
            return .chest
        case .lats, .upperBack, .traps, .lowerBack:
            return .back
        case .frontDelts, .sideDelts, .rearDelts:
            return .shoulders
        case .biceps, .triceps, .forearms:
            return .arms
        case .quads, .hamstrings, .glutes, .calves, .adductors, .abductors:
            return .legs
        case .abs, .obliques:
            return .core
        case .cardio:
            return .cardio
        }
    }

    var accent: Color { system.accent }
}

// MARK: - Equipment (for browsing / disambiguating variants)

nonisolated enum Equipment: String, CaseIterable, Codable, Hashable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, cardio, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell:    "Barbell"
        case .dumbbell:   "Dumbbell"
        case .machine:    "Machine"
        case .cable:      "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band:       "Band"
        case .cardio:     "Cardio"
        case .other:      "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .barbell, .dumbbell, .kettlebell: "dumbbell.fill"
        case .machine:                         "gearshape.fill"
        case .cable:                           "cable.connector"
        case .bodyweight:                      "figure.strengthtraining.functional"
        case .band:                            "line.diagonal"
        case .cardio:                          "figure.run"
        case .other:                           "circle.grid.2x2.fill"
        }
    }
}

// MARK: - Exercise

/// One movement in the library. `primary` are the main movers (<= 2), `secondary`
/// the accessory muscles (<= 2), four total at most. `id` is a stable slug used
/// to persist a logged exercise and to resolve its muscles when reading STYL.
nonisolated struct Exercise: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let equipment: Equipment
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]

    init(_ id: String, _ name: String, _ equipment: Equipment,
         primary: [MuscleGroup], secondary: [MuscleGroup] = []) {
        self.id = id
        self.name = name
        self.equipment = equipment
        // Enforce the spec's cap defensively: at most 2 primary + 2 secondary.
        self.primary = Array(primary.prefix(2))
        self.secondary = Array(secondary.prefix(2))
    }

    /// The region this movement is filed under for browsing (its first primary
    /// mover's system).
    var group: BodySystem { primary.first?.system ?? .core }

    /// All muscles worked, primary first, for compact display.
    var allMuscles: [MuscleGroup] { primary + secondary }

    /// A short "Chest · Triceps" style muscle summary for rows.
    var muscleSummary: String {
        allMuscles.map(\.label).joined(separator: " · ")
    }

    /// Free-text used for fuzzy search / LLM name matching (lowercased tokens).
    var searchHaystack: String {
        (name + " " + equipment.label + " " + allMuscles.map(\.label).joined(separator: " "))
            .lowercased()
    }
}
