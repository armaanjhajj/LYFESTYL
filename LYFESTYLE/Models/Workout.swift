//
//  Workout.swift
//  LYFESTYL
//
//  The structured payload an ACTIVITY entry carries when it's a logged workout.
//  It hangs off `JournalEntry.workout`, so it rides the same offline-safe pipeline
//  and CloudKit sync as everything else (encoded as one JSON blob on the record).
//
//  Sets are optional by design: you can log just the movement and it counts as a
//  single working set; add reps/weight when you want the detail (the "log the
//  exercise, or log every set" promise). Numbers here are the user's own measured
//  input, so they're honest, never estimated by the app.
//

import Foundation

/// One set of one exercise. Both fields optional so a bare "I did this" still
/// reads as a valid set.
nonisolated struct ExerciseSet: Identifiable, Hashable, Codable {
    var id: UUID
    var reps: Int?
    /// Weight in the user's chosen unit (see `WorkoutPayload.unit`).
    var weight: Double?

    init(id: UUID = UUID(), reps: Int? = nil, weight: Double? = nil) {
        self.id = id
        self.reps = reps
        self.weight = weight
    }

    var isEmpty: Bool { reps == nil && weight == nil }
}

/// One exercise inside a session: which movement, and the sets performed. `name`
/// is snapshotted so history still reads even if the library entry changes; the
/// muscles are always resolved live from `exerciseID` via `ExerciseLibrary`.
nonisolated struct LoggedExercise: Identifiable, Hashable, Codable {
    var id: UUID
    var exerciseID: String
    var name: String
    var sets: [ExerciseSet]

    init(id: UUID = UUID(), exerciseID: String, name: String, sets: [ExerciseSet] = []) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
    }

    /// The library entry (nil if this was a free-text movement we couldn't match).
    var exercise: Exercise? { ExerciseLibrary.shared.exercise(id: exerciseID) }

    /// At least one set always counts, even when the user logged no detail.
    var effectiveSetCount: Int { max(sets.count, 1) }

    /// "3 sets" / "3 × 8 · 135 lb" style compact summary for rows.
    func summary(unit: WeightUnit) -> String {
        let n = effectiveSetCount
        let setWord = "\(n) set\(n == 1 ? "" : "s")"
        // If every logged set shares reps/weight, show the tidy "3 × 8 · 135".
        let detailed = sets.filter { !$0.isEmpty }
        guard let first = detailed.first else { return setWord }
        let sameReps = detailed.allSatisfy { $0.reps == first.reps }
        let sameWeight = detailed.allSatisfy { $0.weight == first.weight }
        var parts: [String] = ["\(detailed.count) set\(detailed.count == 1 ? "" : "s")"]
        if sameReps, let reps = first.reps { parts[0] = "\(detailed.count) × \(reps)" }
        if sameWeight, let w = first.weight { parts.append(unit.format(w)) }
        return parts.joined(separator: " · ")
    }
}

/// The unit weights are logged in. Stored on the payload so history stays correct
/// even if the user later flips their preference.
nonisolated enum WeightUnit: String, Codable, Hashable, CaseIterable, Identifiable {
    case lb, kg
    var id: String { rawValue }
    var label: String { rawValue }
    func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded)) : String(rounded)
        return "\(text) \(rawValue)"
    }
}

/// The whole logged session attached to one ACTIVITY entry.
nonisolated struct WorkoutPayload: Hashable, Codable {
    var exercises: [LoggedExercise]
    var unit: WeightUnit

    init(exercises: [LoggedExercise] = [], unit: WeightUnit = .lb) {
        self.exercises = exercises
        self.unit = unit
    }

    var isEmpty: Bool { exercises.isEmpty }
    var exerciseCount: Int { exercises.count }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.effectiveSetCount } }

    /// The distinct body systems this session touched (for the Log footer / detail).
    var systemsWorked: [BodySystem] {
        var seen = Set<BodySystem>()
        var ordered: [BodySystem] = []
        for logged in exercises {
            for muscle in logged.exercise?.allMuscles ?? [] where !seen.contains(muscle.system) {
                seen.insert(muscle.system)
                ordered.append(muscle.system)
            }
        }
        return ordered.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// A short neutral title, e.g. "Push day · 4 exercises" fallback lives in the
    /// store; this is the movement-count line.
    var countSummary: String {
        let e = exerciseCount
        return "\(e) exercise\(e == 1 ? "" : "s") · \(totalSets) set\(totalSets == 1 ? "" : "s")"
    }
}
