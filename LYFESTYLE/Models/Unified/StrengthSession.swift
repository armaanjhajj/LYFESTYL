//
//  StrengthSession.swift
//  LYFESTYL
//
//  The resistance-training payload on a `UnifiedWorkout`. This is the shape Hevy
//  workouts normalize into, and the shape the app's own logger produces, so a
//  Hevy-synced session and a hand-logged one feed the exact same volume, estimated
//  1RM and muscle-balance analysis.
//
//  Units are canonical here: kilograms, meters, seconds. Hevy is kilograms-only at
//  the API level regardless of the user's display preference, so we keep kg as the
//  stored truth and convert at the presentation layer only. That way a user
//  flipping to pounds never rewrites history.
//
//  Nothing is invented. Every metric on a set is optional because which fields are
//  populated depends on how the movement is measured (a plank has duration and no
//  reps, a bodyweight pull-up has reps and no weight). A missing value stays
//  missing rather than becoming a zero that would drag an average down.
//

import Foundation

// MARK: - How a movement is measured

/// The measurement style of a movement, which decides what a "set" even means and
/// therefore which analyses apply. Mirrors Hevy's exercise types so nothing is
/// lost in translation, with an `unknown` fallback because the source can add
/// types at any time.
nonisolated enum StrengthMeasurement: String, Codable, Hashable, Sendable, CaseIterable {
    case weightReps             // load x reps, the classic barbell/dumbbell lift
    case repsOnly               // reps with no load recorded
    case bodyweightReps         // bodyweight movements (pull-ups, push-ups)
    case bodyweightAssistedReps // assisted, where weight is a negative offset
    case duration               // timed holds (planks, dead hangs)
    case weightDuration         // loaded carries and holds
    case distanceDuration       // sled pushes, farmer walks, cardio inside a lift log
    case shortDistanceWeight    // loaded short distance work
    case unknown

    /// Whether `weight x reps` volume load is a meaningful number here. Volume load
    /// only means something when both a load and a rep count exist; summing it for
    /// timed or bodyweight work would produce a figure that looks precise and is not.
    var supportsVolumeLoad: Bool {
        switch self {
        case .weightReps, .weightDuration, .shortDistanceWeight: true
        default: false
        }
    }

    /// Whether an estimated one-rep max can be derived. Needs a real external load
    /// and a countable rep total, and the rep count has to be low enough that the
    /// estimate is not extrapolation (guarded separately in the analysis).
    var supportsOneRepMax: Bool { self == .weightReps }

    /// Whether reps are counted at all (drives "hard sets" tallies).
    var countsReps: Bool {
        switch self {
        case .weightReps, .repsOnly, .bodyweightReps, .bodyweightAssistedReps: true
        default: false
        }
    }

    /// Decode leniently from a source string (Hevy sends snake_case).
    init(sourceValue raw: String?) {
        switch (raw ?? "").lowercased() {
        case "weight_reps":               self = .weightReps
        case "reps_only":                 self = .repsOnly
        case "bodyweight_reps":           self = .bodyweightReps
        case "bodyweight_assisted_reps":  self = .bodyweightAssistedReps
        case "duration":                  self = .duration
        case "weight_duration":           self = .weightDuration
        case "distance_duration":         self = .distanceDuration
        case "short_distance_weight":     self = .shortDistanceWeight
        default:                          self = .unknown
        }
    }
}

// MARK: - What a set targets

/// Which muscle a movement trains. A source sometimes only knows the region
/// ("shoulders") and not the specific head, so this can carry either precision.
/// Recording that honestly means shoulder volume still rolls up correctly to the
/// SHOULDERS system without us inventing a front/side/rear split that the data
/// never contained.
nonisolated enum MuscleTarget: Codable, Hashable, Sendable {
    /// A specific mover, resolved either from the local library or from a source
    /// that names muscles precisely.
    case muscle(MuscleGroup)
    /// Only the region is known (the source was coarse). Counts toward the system.
    case system(BodySystem)
    /// The source named something the app has no concept for (for example "neck",
    /// or "full body", which cannot be attributed to a single region). Preserved
    /// verbatim so it can be displayed, and deliberately excluded from every
    /// balance calculation rather than being forced into the nearest bucket.
    case unmapped(String)

    /// The body system this target contributes to, if it can be attributed at all.
    var system: BodySystem? {
        switch self {
        case .muscle(let m): m.system
        case .system(let s): s
        case .unmapped:      nil
        }
    }

    /// The specific mover, when known.
    var muscle: MuscleGroup? {
        switch self {
        case .muscle(let m): m
        case .system, .unmapped: nil
        }
    }

    var label: String {
        switch self {
        case .muscle(let m):  m.label
        case .system(let s):  s.label.capitalized
        case .unmapped(let s): s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Map a source-provided muscle name onto a target. Handles Hevy's twenty
    /// muscle-group values plus common variants. Anything unrecognized is kept as
    /// `.unmapped` rather than guessed at.
    init(sourceValue raw: String) {
        let key = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "chest", "pectorals":        self = .muscle(.chest)
        case "lats", "latissimus_dorsi":  self = .muscle(.lats)
        case "upper_back":                self = .muscle(.upperBack)
        case "traps", "trapezius":        self = .muscle(.traps)
        case "lower_back":                self = .muscle(.lowerBack)
        case "biceps":                    self = .muscle(.biceps)
        case "triceps":                   self = .muscle(.triceps)
        case "forearms":                  self = .muscle(.forearms)
        case "quadriceps", "quads":       self = .muscle(.quads)
        case "hamstrings":                self = .muscle(.hamstrings)
        case "glutes":                    self = .muscle(.glutes)
        case "calves":                    self = .muscle(.calves)
        case "adductors":                 self = .muscle(.adductors)
        case "abductors":                 self = .muscle(.abductors)
        case "abdominals", "abs":         self = .muscle(.abs)
        case "obliques":                  self = .muscle(.obliques)
        case "cardio":                    self = .muscle(.cardio)
        // Region-only: the source did not say which head or which muscle.
        case "shoulders", "deltoids", "delts": self = .system(.shoulders)
        case "back":                      self = .system(.back)
        case "legs":                      self = .system(.legs)
        case "arms":                      self = .system(.arms)
        case "core":                      self = .system(.core)
        // Not attributable to one region without inventing a split.
        default:                          self = .unmapped(key)
        }
    }
}

// MARK: - Set

nonisolated enum StrengthSetType: String, Codable, Hashable, Sendable, CaseIterable {
    case normal
    case warmup
    case dropset
    case failure
    /// The source sent a type we do not model yet. Treated as a working set,
    /// because dropping it would understate volume.
    case unknown

    var label: String {
        switch self {
        case .normal:  "Working"
        case .warmup:  "Warm-up"
        case .dropset: "Drop set"
        case .failure: "To failure"
        case .unknown: "Set"
        }
    }

    /// Warm-ups are excluded from working-volume and hard-set tallies. Everything
    /// else counts, including drop sets and sets taken to failure.
    var countsAsWorkingSet: Bool { self != .warmup }

    init(sourceValue raw: String?) {
        switch (raw ?? "").lowercased() {
        case "normal":  self = .normal
        case "warmup", "warm_up": self = .warmup
        case "dropset", "drop_set": self = .dropset
        case "failure": self = .failure
        default:        self = .unknown
        }
    }
}

/// One set. Every metric is optional: what is populated depends on the movement's
/// measurement style, and an absent value is absent, never zero.
nonisolated struct StrengthSet: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    /// Position within the exercise, preserved from the source so order is stable.
    var index: Int
    var type: StrengthSetType
    /// External load in kilograms. Negative on assisted movements, where the value
    /// is the assistance rather than the load.
    var weightKg: Double?
    var reps: Int?
    var distanceMeters: Double?
    var durationSeconds: Double?
    /// Rate of perceived exertion, 0 to 10 where the source provides it.
    var rpe: Double?

    init(
        id: UUID = UUID(),
        index: Int,
        type: StrengthSetType = .normal,
        weightKg: Double? = nil,
        reps: Int? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Double? = nil,
        rpe: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.type = type
        self.weightKg = weightKg
        self.reps = reps
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.rpe = rpe
    }

    var isWorkingSet: Bool { type.countsAsWorkingSet }

    /// Volume load in kilograms (load x reps). Nil unless both parts are present
    /// and the load is a real positive external load.
    var volumeLoadKg: Double? {
        guard let w = weightKg, w > 0, let r = reps, r > 0 else { return nil }
        return w * Double(r)
    }

    /// Reps in reserve implied by RPE, on the standard RPE-to-RIR mapping where an
    /// RPE of 10 is zero reps left. Nil when the set carries no RPE.
    var repsInReserve: Double? {
        guard let rpe else { return nil }
        return max(0, 10 - rpe)
    }

    var isEmpty: Bool {
        weightKg == nil && reps == nil && distanceMeters == nil && durationSeconds == nil
    }
}

// MARK: - Exercise

/// One movement inside a session, with the sets performed. Muscle attribution
/// prefers the local `ExerciseLibrary` (which knows front vs side vs rear delts)
/// and falls back to whatever the source provided.
nonisolated struct StrengthExercise: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var index: Int
    /// The movement name as the source recorded it, kept verbatim so history reads
    /// the way the user logged it.
    var name: String
    /// The source's own template identifier (Hevy's `exercise_template_id`), which
    /// is what makes per-exercise history reliable even if the display name changes.
    var templateID: String?
    /// The matched entry in the app's own `ExerciseLibrary`, when we could resolve
    /// one. Gives precise muscle tags and ties synced work to hand-logged work.
    var libraryExerciseID: String?
    var notes: String?
    /// Groups movements performed as a superset, as numbered by the source.
    var supersetID: Int?
    var measurement: StrengthMeasurement
    var primaryTargets: [MuscleTarget]
    var secondaryTargets: [MuscleTarget]
    var equipment: Equipment
    var sets: [StrengthSet]

    init(
        id: UUID = UUID(),
        index: Int,
        name: String,
        templateID: String? = nil,
        libraryExerciseID: String? = nil,
        notes: String? = nil,
        supersetID: Int? = nil,
        measurement: StrengthMeasurement = .weightReps,
        primaryTargets: [MuscleTarget] = [],
        secondaryTargets: [MuscleTarget] = [],
        equipment: Equipment = .other,
        sets: [StrengthSet] = []
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.templateID = templateID
        self.libraryExerciseID = libraryExerciseID
        self.notes = notes
        self.supersetID = supersetID
        self.measurement = measurement
        self.primaryTargets = primaryTargets
        self.secondaryTargets = secondaryTargets
        self.equipment = equipment
        self.sets = sets
    }

    /// The library entry, when this movement resolved to one.
    var libraryExercise: Exercise? {
        libraryExerciseID.flatMap { ExerciseLibrary.shared.exercise(id: $0) }
    }

    var workingSets: [StrengthSet] { sets.filter(\.isWorkingSet) }
    var workingSetCount: Int { workingSets.count }

    /// Total working volume load, nil when the movement is not load-and-reps based
    /// or no set carried both numbers.
    var volumeLoadKg: Double? {
        guard measurement.supportsVolumeLoad else { return nil }
        let values = workingSets.compactMap(\.volumeLoadKg)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var totalReps: Int? {
        guard measurement.countsReps else { return nil }
        let values = workingSets.compactMap(\.reps)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Heaviest working load lifted for at least one rep.
    var topSetWeightKg: Double? {
        workingSets.compactMap { set -> Double? in
            guard let w = set.weightKg, w > 0, let r = set.reps, r > 0 else { return nil }
            return w
        }.max()
    }

    /// A stable key for tracking this exercise across sessions. Prefers the
    /// source template id, then the resolved library id, then a normalized name,
    /// so per-exercise trends survive a rename.
    var trackingKey: String {
        if let templateID, !templateID.isEmpty { return "tpl:\(templateID)" }
        if let libraryExerciseID, !libraryExerciseID.isEmpty { return "lib:\(libraryExerciseID)" }
        return "name:" + name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every target this movement trains, primaries first.
    var allTargets: [MuscleTarget] { primaryTargets + secondaryTargets }

    /// The regions this movement touches, deduplicated.
    var systems: [BodySystem] {
        var seen = Set<BodySystem>()
        var ordered: [BodySystem] = []
        for target in allTargets {
            guard let system = target.system, !seen.contains(system) else { continue }
            seen.insert(system)
            ordered.append(system)
        }
        return ordered.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// "4 x 8 at 100 kg" style compact summary, or the honest looser form when
    /// sets varied. Formats in the caller's preferred unit.
    func summary(unit: WeightUnit) -> String {
        let working = workingSets
        let n = working.count
        guard n > 0 else { return "No sets recorded" }
        let setWord = "\(n) set\(n == 1 ? "" : "s")"

        let detailed = working.filter { !$0.isEmpty }
        guard let first = detailed.first else { return setWord }
        let sameReps = detailed.allSatisfy { $0.reps == first.reps }
        let sameWeight = detailed.allSatisfy { $0.weightKg == first.weightKg }

        var head = "\(detailed.count) set\(detailed.count == 1 ? "" : "s")"
        if sameReps, let reps = first.reps { head = "\(detailed.count) x \(reps)" }

        var parts = [head]
        if sameWeight, let kg = first.weightKg, kg != 0 {
            parts.append(unit.formatKilograms(kg))
        } else if let heaviest = topSetWeightKg {
            parts.append("top \(unit.formatKilograms(heaviest))")
        }
        if measurement == .duration || measurement == .weightDuration {
            let seconds = detailed.compactMap(\.durationSeconds).reduce(0, +)
            if seconds > 0 { parts.append(Self.durationText(seconds)) }
        }
        return parts.joined(separator: " · ")
    }

    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

// MARK: - Session

/// The whole resistance-training session hanging off a `UnifiedWorkout`.
nonisolated struct StrengthSession: Hashable, Codable, Sendable {
    var exercises: [StrengthExercise]

    init(exercises: [StrengthExercise] = []) {
        self.exercises = exercises
    }

    var isEmpty: Bool { exercises.isEmpty }
    var exerciseCount: Int { exercises.count }
    var workingSetCount: Int { exercises.reduce(0) { $0 + $1.workingSetCount } }
    var totalSetCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Session volume load in kilograms, summed only over movements where the
    /// figure is meaningful. Nil when nothing in the session qualified.
    var volumeLoadKg: Double? {
        let values = exercises.compactMap(\.volumeLoadKg)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var totalReps: Int? {
        let values = exercises.compactMap(\.totalReps)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Mean RPE across working sets that carried one.
    var averageRPE: Double? {
        let values = exercises.flatMap { $0.workingSets }.compactMap(\.rpe)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The regions this session touched, in display order.
    var systemsWorked: [BodySystem] {
        var seen = Set<BodySystem>()
        var ordered: [BodySystem] = []
        for exercise in exercises {
            for system in exercise.systems where !seen.contains(system) {
                seen.insert(system)
                ordered.append(system)
            }
        }
        return ordered.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Working sets credited per body system. A set counts 1.0 toward each region
    /// its primary movers belong to and 0.5 toward accessory regions, which is the
    /// same weighting the existing muscle-balance read uses so synced and hand
    /// logged work are directly comparable.
    ///
    /// Targets the app cannot attribute (`.unmapped`) are excluded rather than
    /// forced into a bucket.
    func setsPerSystem() -> [BodySystem: Double] {
        var result: [BodySystem: Double] = [:]
        for exercise in exercises {
            let n = Double(exercise.workingSetCount)
            guard n > 0 else { continue }
            var creditedPrimary = Set<BodySystem>()
            for target in exercise.primaryTargets {
                guard let system = target.system else { continue }
                guard creditedPrimary.insert(system).inserted else { continue }
                result[system, default: 0] += n
            }
            for target in exercise.secondaryTargets {
                guard let system = target.system, !creditedPrimary.contains(system) else { continue }
                result[system, default: 0] += n * 0.5
            }
        }
        return result
    }

    /// Working sets credited per specific muscle, same weighting. Only movements
    /// with precise muscle attribution contribute, so this is empty when every
    /// source was region-only.
    func setsPerMuscle() -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for exercise in exercises {
            let n = Double(exercise.workingSetCount)
            guard n > 0 else { continue }
            for target in exercise.primaryTargets {
                guard let muscle = target.muscle else { continue }
                result[muscle, default: 0] += n
            }
            for target in exercise.secondaryTargets {
                guard let muscle = target.muscle else { continue }
                result[muscle, default: 0] += n * 0.5
            }
        }
        return result
    }

    /// "5 exercises · 21 sets" line for rows.
    var countSummary: String {
        let e = exerciseCount
        let s = workingSetCount
        return "\(e) exercise\(e == 1 ? "" : "s") · \(s) set\(s == 1 ? "" : "s")"
    }
}

// MARK: - Unit formatting

nonisolated extension WeightUnit {
    /// Kilograms per pound, exact by definition (1 lb = 0.45359237 kg).
    static let kilogramsPerPound = 0.45359237

    /// Convert a canonical kilogram value into this unit.
    func fromKilograms(_ kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lb: kg / Self.kilogramsPerPound
        }
    }

    /// Convert a value in this unit back to canonical kilograms.
    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value * Self.kilogramsPerPound
        }
    }

    /// Format a canonical kilogram value for display in this unit.
    func formatKilograms(_ kg: Double) -> String {
        format(fromKilograms(kg))
    }
}
