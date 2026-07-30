//
//  HevyMapper.swift
//  LYFESTYL
//
//  Turns Hevy's wire types into the app's canonical `UnifiedWorkout`.
//
//  The important work here is MUSCLE ATTRIBUTION, because that is what makes per-muscle
//  weekly volume possible. Three sources are tried, best first:
//
//    1. The app's own `ExerciseLibrary`, matched on the movement name. This is the most
//       precise, because the library distinguishes front, side and rear delts where Hevy
//       only says "shoulders".
//    2. Hevy's exercise template, which names a primary muscle group and secondaries.
//       Coarser, but authoritative for custom movements the library has never seen.
//    3. Nothing. The exercise is still recorded with its sets, and simply does not
//       contribute to the balance read.
//
//  A movement is never assigned a guessed muscle. When only the region is known, that is
//  recorded AS a region (see `MuscleTarget`), so shoulder volume rolls up correctly to the
//  SHOULDERS system without inventing a front/side/rear split that the data never had.
//

import Foundation

// MARK: - Template cache

/// Hevy's exercise-template catalog, cached locally.
///
/// Worth caching because templates change rarely, the endpoint is the only one that allows
/// 100 items per page, and every workout references templates by id. Fetching the catalog
/// once turns muscle attribution into a dictionary lookup instead of a request per set.
nonisolated struct HevyTemplateCache: Codable, Sendable {
    struct Template: Codable, Sendable, Hashable {
        var id: String
        var title: String
        /// Hevy's exercise type, which decides what a set even means.
        var type: String?
        var primaryMuscleGroup: String?
        var secondaryMuscleGroups: [String]
        var equipmentValue: String?
        var isCustom: Bool

        var measurement: StrengthMeasurement { StrengthMeasurement(sourceValue: type) }

        var primaryTargets: [MuscleTarget] {
            guard let primaryMuscleGroup, !primaryMuscleGroup.isEmpty else { return [] }
            return [MuscleTarget(sourceValue: primaryMuscleGroup)]
        }

        var secondaryTargets: [MuscleTarget] {
            secondaryMuscleGroups
                .filter { !$0.isEmpty }
                .map { MuscleTarget(sourceValue: $0) }
        }

        var equipment: Equipment { HevyMapper.equipment(from: equipmentValue) }
    }

    var templatesByID: [String: Template]
    var fetchedAt: Date?

    init(templatesByID: [String: Template] = [:], fetchedAt: Date? = nil) {
        self.templatesByID = templatesByID
        self.fetchedAt = fetchedAt
    }

    static let empty = HevyTemplateCache()

    var isEmpty: Bool { templatesByID.isEmpty }
    var count: Int { templatesByID.count }

    /// Templates go stale slowly. Refetching weekly is plenty, and avoids spending the
    /// undocumented rate limit on data that has not changed.
    var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > 7 * 24 * 3600
    }

    func template(id: String?) -> Template? {
        guard let id, !id.isEmpty else { return nil }
        return templatesByID[id]
    }

    mutating func insert(_ dtos: [HevyExerciseTemplateDTO]) {
        for dto in dtos {
            guard let id = dto.id, !id.isEmpty else { continue }
            templatesByID[id] = Template(
                id: id,
                title: dto.title ?? "Exercise",
                type: dto.type,
                primaryMuscleGroup: dto.primary_muscle_group,
                secondaryMuscleGroups: dto.secondary_muscle_groups ?? [],
                equipmentValue: dto.equipment,
                isCustom: dto.is_custom ?? false
            )
        }
    }
}

// MARK: - Mapper

nonisolated enum HevyMapper {

    /// Map one Hevy workout. Returns nil when it lacks the times needed to place it in a
    /// history, which no real workout does.
    static func workout(
        from dto: HevyWorkoutDTO,
        templates: HevyTemplateCache,
        calendar: Calendar = .current
    ) -> UnifiedWorkout? {
        guard let id = dto.id, !id.isEmpty else { return nil }
        guard let start = HevyDate.date(from: dto.start_time) else { return nil }
        // A workout with no end time is one still in progress; fall back to start so it
        // still appears rather than vanishing.
        let end = HevyDate.date(from: dto.end_time) ?? start

        let exercises = (dto.exercises ?? []).enumerated().compactMap { index, exerciseDTO in
            exercise(from: exerciseDTO, fallbackIndex: index, templates: templates)
        }
        let strength = exercises.isEmpty ? nil : StrengthSession(exercises: exercises)

        let origin = SourceRef(
            source: .hevy,
            foreignID: id,
            updatedAt: HevyDate.date(from: dto.updated_at)
        )

        // Hevy records elapsed wall-clock time only. It has no notion of paused time, so
        // moving time is the same figure rather than an invented smaller one.
        let elapsed = max(0, end.timeIntervalSince(start))

        // Hevy carries per-set RPE but no session RPE. Deriving one lets the training-load
        // model score lifting sessions at all, and it comes from numbers the user actually
        // entered rather than an assumption.
        let sessionRPE = strength.flatMap { TrainingLoad.impliedSessionRPE(for: $0) }

        let title = (dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? defaultTitle(start: start, strength: strength)

        let notes = (dto.description?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        }

        return UnifiedWorkout(
            id: origin.uniqueKey,
            origin: origin,
            sport: sport(for: strength),
            title: title,
            notes: notes,
            start: start,
            end: end,
            movingSeconds: elapsed,
            isIndoor: true,
            perceivedEffort: sessionRPE,
            strength: strength,
            calendar: calendar
        )
    }

    /// Map one exercise, resolving its muscles.
    static func exercise(
        from dto: HevyExerciseDTO,
        fallbackIndex: Int,
        templates: HevyTemplateCache
    ) -> StrengthExercise? {
        let rawName = (dto.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let template = templates.template(id: dto.exercise_template_id)
        let name = rawName.isEmpty ? (template?.title ?? "Exercise") : rawName
        guard !name.isEmpty else { return nil }

        let sets = (dto.sets ?? []).enumerated().map { index, setDTO in
            set(from: setDTO, fallbackIndex: index)
        }
        // An exercise with no sets was still opened and is worth keeping, but it
        // contributes no volume.

        // Attribution, best source first.
        let libraryMatch = ExerciseLibrary.shared.match(name: name)
        let primary: [MuscleTarget]
        let secondary: [MuscleTarget]
        if let libraryMatch, !libraryMatch.primary.isEmpty {
            primary = libraryMatch.primary.map { MuscleTarget.muscle($0) }
            secondary = libraryMatch.secondary.map { MuscleTarget.muscle($0) }
        } else {
            primary = template?.primaryTargets ?? []
            secondary = template?.secondaryTargets ?? []
        }

        let measurement = template?.measurement
            ?? inferMeasurement(from: sets)

        return StrengthExercise(
            index: dto.index ?? fallbackIndex,
            name: libraryMatch?.name ?? name,
            templateID: dto.exercise_template_id,
            libraryExerciseID: libraryMatch?.id,
            notes: (dto.notes?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            },
            supersetID: dto.superset_id,
            measurement: measurement,
            primaryTargets: primary,
            secondaryTargets: secondary,
            equipment: libraryMatch?.equipment ?? template?.equipment ?? .other,
            sets: sets
        )
    }

    static func set(from dto: HevySetDTO, fallbackIndex: Int) -> StrengthSet {
        StrengthSet(
            index: dto.index ?? fallbackIndex,
            type: StrengthSetType(sourceValue: dto.type),
            // Hevy is kilograms-only at the API level, matching our canonical unit.
            weightKg: dto.weight_kg,
            reps: dto.reps,
            distanceMeters: dto.distance_meters,
            durationSeconds: dto.duration_seconds,
            rpe: dto.rpe
        )
    }

    /// When no template is cached, infer how a movement is measured from what its sets
    /// actually contain. Better than defaulting to weight-and-reps, which would make
    /// volume load appear for a plank.
    static func inferMeasurement(from sets: [StrengthSet]) -> StrengthMeasurement {
        let hasWeight = sets.contains { ($0.weightKg ?? 0) != 0 }
        let hasReps = sets.contains { ($0.reps ?? 0) > 0 }
        let hasDuration = sets.contains { ($0.durationSeconds ?? 0) > 0 }
        let hasDistance = sets.contains { ($0.distanceMeters ?? 0) > 0 }

        switch (hasWeight, hasReps, hasDuration, hasDistance) {
        case (true, true, _, _):      return .weightReps
        case (true, false, true, _):  return .weightDuration
        case (false, true, _, _):     return .repsOnly
        case (false, false, true, true): return .distanceDuration
        case (false, false, true, false): return .duration
        default:                      return .unknown
        }
    }

    /// Hevy is a lifting log, so a session is a strength session unless every movement in
    /// it is measured as distance-and-duration, which is how people log cardio there.
    static func sport(for strength: StrengthSession?) -> WorkoutSport {
        guard let strength, !strength.exercises.isEmpty else { return .strengthTraining }
        let cardioLike = strength.exercises.allSatisfy {
            $0.measurement == .distanceDuration || $0.measurement == .duration
        }
        return cardioLike ? .crossTraining : .strengthTraining
    }

    /// Map Hevy's nine equipment categories onto ours.
    static func equipment(from category: String?) -> Equipment {
        switch (category ?? "").lowercased() {
        case "barbell":         .barbell
        case "dumbbell":        .dumbbell
        case "kettlebell":      .kettlebell
        case "machine":         .machine
        case "plate":           .machine
        case "resistance_band": .band
        case "suspension":      .bodyweight
        case "none":            .bodyweight
        default:                .other
        }
    }

    /// A neutral title when the user left Hevy's default blank.
    private static func defaultTitle(start: Date, strength: StrengthSession?) -> String {
        let systems = strength?.systemsWorked ?? []
        switch systems.count {
        case 0:  return "Workout"
        case 1:  return "\(systems[0].label.capitalized) session"
        default: return "\(systems[0].label.capitalized) and \(systems[1].label.capitalized)"
        }
    }

    // MARK: - Body measurements

    /// Fold Hevy's body measurements into daily snapshots. Hevy is often where someone
    /// actually records their weight, so this is a real source rather than a nicety.
    static func snapshots(
        from measurements: [HevyBodyMeasurementDTO],
        calendar: Calendar = .current
    ) -> [DailySnapshot] {
        measurements.compactMap { dto -> DailySnapshot? in
            guard let date = HevyDate.day(from: dto.date) else { return nil }
            let snapshot = DailySnapshot(
                date: calendar.startOfDay(for: date),
                bodyMassKg: plausible(dto.weight_kg, 25...350),
                bodyFatPercent: plausible(dto.fat_percent, 2...70),
                leanBodyMassKg: plausible(dto.lean_mass_kg, 10...200),
                contributingSources: [.hevy]
            )
            return snapshot.isEmpty ? nil : snapshot
        }
    }

    private static func plausible(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }
}
