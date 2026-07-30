//
//  LegacyWorkoutBridge.swift
//  LYFESTYL
//
//  Converts the app's ORIGINAL workout shape into the canonical one.
//
//  Before the aggregation feature there were two workout models: `WorkoutPayload` hanging off a
//  journal entry for hand-logged sessions, and `UnifiedWorkout` for everything synced. That
//  meant two muscle-balance implementations, two activity lists and two sets of trends, and a
//  session you logged yourself was analysed differently from the identical session synced from
//  Hevy. This file is what collapses the two.
//
//  `UnifiedWorkout` is now the single model. `WorkoutPayload` survives only so that entries
//  already saved to CloudKit and the local cache can still be read and migrated, which is why
//  the conversion lives here rather than as a method on the old type: it is a one-way bridge
//  out of a format nothing writes any more.
//
//  Migration is IDEMPOTENT and NON-DESTRUCTIVE. It derives a deterministic id from the entry's
//  UUID, so re-running it updates the same workout rather than creating another, and it leaves
//  the journal entry untouched. Nothing is deleted, and running it twice is a no-op.
//

import Foundation

nonisolated enum LegacyWorkoutBridge {

    /// Convert a legacy payload into the canonical strength session.
    ///
    /// The old model stored weight in whatever unit the user was typing in, carried on the
    /// payload. The canonical model is kilograms throughout, so this converts on the way
    /// across; getting that backwards would silently inflate every volume figure by 2.2.
    static func strengthSession(from payload: WorkoutPayload) -> StrengthSession? {
        let exercises = payload.exercises.enumerated().map { index, logged -> StrengthExercise in
            let library = logged.exercise
            let sets = logged.sets.enumerated().map { setIndex, set in
                StrengthSet(
                    index: setIndex,
                    type: .normal,
                    weightKg: set.weight.map { payload.unit.toKilograms($0) },
                    reps: set.reps
                )
            }
            return StrengthExercise(
                index: index,
                name: logged.name,
                templateID: nil,
                libraryExerciseID: library?.id ?? (logged.exerciseID.isEmpty ? nil : logged.exerciseID),
                measurement: .weightReps,
                primaryTargets: (library?.primary ?? []).map { MuscleTarget.muscle($0) },
                secondaryTargets: (library?.secondary ?? []).map { MuscleTarget.muscle($0) },
                equipment: library?.equipment ?? .other,
                sets: sets
            )
        }
        return exercises.isEmpty ? nil : StrengthSession(exercises: exercises)
    }

    /// The deterministic identity a migrated entry maps to, so migration can run repeatedly.
    static func identity(for entryID: UUID) -> SourceRef {
        SourceRef(source: .manual, foreignID: "entry-\(entryID.uuidString)")
    }

    /// Convert one journal entry into a workout, when it carries one.
    ///
    /// Returns nil for entries that are not logged sessions. An ACTIVITY entry that is just
    /// written text stays a journal entry: it has no structure to analyse, and promoting it
    /// would put an empty session in the training history.
    static func workout(from entry: JournalEntry, calendar: Calendar = .current) -> UnifiedWorkout? {
        guard entry.category == .activity, let payload = entry.workout,
              let strength = strengthSession(from: payload) else { return nil }

        let origin = identity(for: entry.id)
        // The old model recorded no duration, so the session is given a nominal length derived
        // from its volume rather than a made-up fixed number: roughly three minutes per working
        // set is the usual pace including rest. It is clearly an estimate, and it only affects
        // the duration-based load fallback.
        let estimatedSeconds = Double(max(1, strength.workingSetCount)) * 180

        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: .strengthTraining,
            title: entry.listTitle,
            notes: entry.rawText.isEmpty ? nil : entry.rawText,
            start: entry.createdAt,
            end: entry.createdAt.addingTimeInterval(estimatedSeconds),
            movingSeconds: estimatedSeconds,
            isIndoor: true,
            strength: strength,
            calendar: calendar
        )
    }

    /// Migrate a whole journal history.
    ///
    /// Only produces workouts the caller does not already have, so it is safe to run on every
    /// launch. Existing ids win, which means a session later re-synced from Hevy with richer
    /// data is never overwritten by its migrated placeholder.
    static func migrate(
        entries: [JournalEntry],
        existing: [UnifiedWorkout],
        calendar: Calendar = .current
    ) -> [UnifiedWorkout] {
        let known = Set(existing.map(\.id))
        return entries.compactMap { entry in
            guard let workout = workout(from: entry, calendar: calendar),
                  !known.contains(workout.id) else { return nil }
            return workout
        }
    }
}
