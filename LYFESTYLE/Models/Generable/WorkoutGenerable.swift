//
//  WorkoutGenerable.swift
//  LYFESTYL
//
//  Guided Generation schemas (CLAUDE.md §1) for the two on-device workout jobs:
//    1. ParsedWorkout — turn a free-written note ("push day, some chest press and
//       a few sets of incline") into structured movements we can match to the
//       library and log alongside the raw text.
//    2. WorkoutSuggestion — propose a balanced next session from the user's recent
//       muscle load. Suggestion, never judgment (quiet-AI direction): it fills gaps
//       in what's been trained, it doesn't grade the user.
//
//  Everything runs on-device via FoundationModels; nothing leaves the phone.
//

import FoundationModels

// MARK: - Parsing a free-written workout

@Generable
struct ParsedWorkout: Equatable {
    @Guide(description: "Every distinct exercise the person mentioned doing, in order. If the note is vague ('push day') infer the specific movements a lifter would typically do for it. If the note isn't about a workout at all, return an empty list.")
    var exercises: [ParsedExercise]
}

@Generable
struct ParsedExercise: Equatable {
    @Guide(description: "The exercise's common gym name, as specific as the note allows, e.g. 'Barbell Bench Press', 'Incline Dumbbell Press', 'Lat Pulldown', 'Barbell Back Squat', 'Running'. Prefer standard names over slang.")
    var name: String

    @Guide(description: "How many sets they did, if stated or clearly implied. Leave empty if unknown.")
    var sets: Int?

    @Guide(description: "Reps per set, if stated. Leave empty if unknown.")
    var reps: Int?

    @Guide(description: "Weight per set as a plain number in the same unit the person used (pounds or kilos), if stated. Leave empty if unknown.")
    var weight: Double?
}

// MARK: - Suggesting a next session

@Generable
struct WorkoutSuggestion: Equatable {
    @Guide(description: "A short, neutral focus for the session, 2 to 5 words, e.g. 'Legs and core', 'Pull day', 'Easy cardio + arms'. No hype, no rating.")
    var focus: String

    @Guide(description: "3 to 6 concrete exercises for the session, ordered as you'd do them. Use standard gym names.")
    var items: [SuggestedItem]

    @Guide(description: "One calm sentence explaining why this session fits what they've been training lately (e.g. which areas have been light). No judgement, no praise, no em dashes.")
    var note: String
}

@Generable
struct SuggestedItem: Equatable {
    @Guide(description: "The exercise's common gym name, e.g. 'Romanian Deadlift', 'Cable Row', 'Plank'.")
    var name: String

    @Guide(description: "Suggested number of sets, a small whole number (2 to 5).")
    var sets: Int

    @Guide(description: "Suggested reps per set (a whole number, or a duration in seconds for holds/cardio).")
    var reps: Int
}
