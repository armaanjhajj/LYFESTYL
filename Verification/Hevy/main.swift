//
//  main.swift
//  Verification/Hevy
//
//  Decodes REAL Hevy API responses through the app's actual DTOs and mapper, then asserts
//  that the fields we depend on genuinely arrived.
//
//  This exists because Hevy's published OpenAPI document is stale, and a wrong key name in a
//  `Decodable` struct fails SILENTLY: the property is simply nil and the app carries on with
//  missing data. Checking against the spec is not enough; only real responses settle it.
//
//  It found three real bugs on first run:
//    - the read path returns `superset_id`, not the spec's `supersets_id`
//    - exercise templates return `equipment`, not the spec's `equipment_category`
//    - the exercise-type enum omits `bodyweight_weighted`, `bodyweight_assisted`,
//      `floors_duration` and `steps_duration`
//
//  Usage. Fetch fresh samples with your own key, then run:
//
//    export HEVY_API_KEY=...
//    ./Verification/Hevy/fetch.sh
//    swiftc -O -o /tmp/hevycheck \
//      LYFESTYLE/Models/Unified/*.swift LYFESTYLE/Services/Analytics/*.swift \
//      LYFESTYLE/Models/HealthInsight.swift LYFESTYLE/Models/Exercise.swift \
//      LYFESTYLE/Models/ExerciseLibrary.swift LYFESTYLE/Models/Workout.swift \
//      LYFESTYLE/Models/JournalEntry.swift LYFESTYLE/DesignSystem/SolarizedPalette.swift \
//      LYFESTYLE/DesignSystem/Formatting.swift LYFESTYLE/DesignSystem/InsightCategory.swift \
//      LYFESTYLE/Services/Integrations/HevyAPI.swift \
//      LYFESTYLE/Services/Integrations/HevyMapper.swift Verification/Hevy/main.swift
//    /tmp/hevycheck Verification/Hevy/samples
//
//  The samples directory is gitignored: it contains one person's training history.
//

import Foundation

var failures: [String] = []
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        let extra = detail()
        failures.append("  \(name)\(extra.isEmpty ? "" : ": \(extra)")")
    }
}

let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Verification/Hevy/samples"
let fm = FileManager.default

func load(_ name: String) -> Data? {
    fm.contents(atPath: "\(directory)/\(name)")
}

guard let workoutsData = load("workouts.json"),
      let templatesData = load("templates.json") else {
    print("No samples in \(directory). Run ./Verification/Hevy/fetch.sh with HEVY_API_KEY set.")
    exit(2)
}

let decoder = JSONDecoder()

// These envelopes are `private` inside HevyAPI, so they are restated here. If the real shape
// ever changes, this decode fails loudly rather than the app quietly seeing nothing.
struct WorkoutPage: Decodable { var page: Int?; var page_count: Int?; var workouts: [HevyWorkoutDTO]? }
struct TemplatePage: Decodable { var page: Int?; var page_count: Int?; var exercise_templates: [HevyExerciseTemplateDTO]? }

// MARK: - Templates

guard let templatePage = try? decoder.decode(TemplatePage.self, from: templatesData),
      let templateDTOs = templatePage.exercise_templates, !templateDTOs.isEmpty else {
    print("FAILED to decode templates.json"); exit(1)
}
var cache = HevyTemplateCache()
cache.insert(templateDTOs)
print("Templates decoded: \(cache.count)")

check("templates decoded", cache.count > 0)
let withMuscle = cache.templatesByID.values.filter { $0.primaryMuscleGroup?.isEmpty == false }
check("templates carry a primary muscle group",
      Double(withMuscle.count) / Double(cache.count) > 0.9,
      "\(withMuscle.count) of \(cache.count)")
// The bug that made this file necessary: the spec's `equipment_category` decoded to nil for
// every template.
let withEquipment = cache.templatesByID.values.filter { $0.equipmentValue?.isEmpty == false }
check("templates carry equipment",
      !withEquipment.isEmpty,
      "\(withEquipment.count) of \(cache.count) had a non-nil equipment value")

// Every exercise type the live API sends must map to something other than `.unknown`.
var unknownTypes = Set<String>()
for template in cache.templatesByID.values {
    if template.measurement == .unknown, let raw = template.type, !raw.isEmpty {
        unknownTypes.insert(raw)
    }
}
check("every exercise type is mapped", unknownTypes.isEmpty,
      "unmapped: \(unknownTypes.sorted().joined(separator: ", "))")

// Every muscle group must map to a real target rather than falling through to `.unmapped`,
// except the ones that genuinely cannot be attributed to one region.
let deliberatelyUnmapped: Set<String> = ["full_body", "neck", "other"]
var unmappedMuscles = Set<String>()
for template in cache.templatesByID.values {
    for target in template.primaryTargets + template.secondaryTargets {
        if case .unmapped(let raw) = target, !deliberatelyUnmapped.contains(raw) {
            unmappedMuscles.insert(raw)
        }
    }
}
check("every muscle group is mapped", unmappedMuscles.isEmpty,
      "unmapped: \(unmappedMuscles.sorted().joined(separator: ", "))")

// MARK: - Workouts

guard let workoutPage = try? decoder.decode(WorkoutPage.self, from: workoutsData),
      let dtos = workoutPage.workouts, !dtos.isEmpty else {
    print("FAILED to decode workouts.json"); exit(1)
}
print("Workouts decoded: \(dtos.count)")

check("workouts decoded", !dtos.isEmpty)
check("workout ids present", dtos.allSatisfy { $0.id?.isEmpty == false })

// Dates. The live API uses TWO different formats on the same object: start and end carry a
// `+00:00` offset, while created and updated carry `Z` with fractional seconds. Both must parse.
var startParsed = 0, updatedParsed = 0
for dto in dtos {
    if HevyDate.date(from: dto.start_time) != nil { startParsed += 1 }
    if HevyDate.date(from: dto.updated_at) != nil { updatedParsed += 1 }
}
check("start_time parses (offset form)", startParsed == dtos.count, "\(startParsed) of \(dtos.count)")
check("updated_at parses (Z with fractional seconds)", updatedParsed == dtos.count,
      "\(updatedParsed) of \(dtos.count)")

// Supersets. The spec's field name decoded to nil for every workout; the live name does not.
let supersetCount = dtos.flatMap { $0.exercises ?? [] }.filter { $0.superset_id != nil }.count
check("supersets decode", supersetCount > 0,
      "no exercise carried a superset id across \(dtos.count) workouts")

// MARK: - Mapping

let mapped = dtos.compactMap { HevyMapper.workout(from: $0, templates: cache) }
print("Mapped to UnifiedWorkout: \(mapped.count)")
check("every workout maps", mapped.count == dtos.count, "\(mapped.count) of \(dtos.count)")

let withStrength = mapped.filter { $0.strength != nil }
check("sessions carry a strength payload", withStrength.count == mapped.count,
      "\(withStrength.count) of \(mapped.count)")

let totalSets = mapped.reduce(0) { $0 + ($1.strength?.workingSetCount ?? 0) }
check("working sets counted", totalSets > 0, "\(totalSets)")

// Muscle attribution is what makes weekly volume possible, so it is the thing most worth
// asserting on real data.
var attributed = 0, unattributed = 0
var unattributedNames = Set<String>()
for workout in mapped {
    for exercise in workout.strength?.exercises ?? [] {
        if exercise.systems.isEmpty {
            unattributed += 1
            unattributedNames.insert(exercise.name)
        } else {
            attributed += 1
        }
    }
}
let attributionRate = Double(attributed) / Double(max(1, attributed + unattributed))
check("most exercises resolve to a body region", attributionRate > 0.85,
      String(format: "%.1f%% attributed, %d unattributed", attributionRate * 100, unattributed))
print(String(format: "Muscle attribution: %.1f%% (%d attributed, %d not)",
             attributionRate * 100, attributed, unattributed))
if !unattributedNames.isEmpty {
    print("  unattributed: " + unattributedNames.sorted().prefix(8).joined(separator: ", "))
}

// Volume load must be a real number on load-and-reps work.
let withVolume = mapped.compactMap { $0.strength?.volumeLoadKg }
check("volume load computed", !withVolume.isEmpty, "\(withVolume.count) of \(mapped.count)")
if let median = Stats.median(withVolume) {
    // A session between 500 kg and 100 t of total volume is the plausible human range.
    check("volume load is plausible", median > 500 && median < 100_000,
          String(format: "median %.0f kg", median))
    print(String(format: "Volume load: median %.0f kg per session", median))
}

// Estimated one-rep max on real sets.
var oneRepMaxes: [Double] = []
for workout in mapped {
    for exercise in workout.strength?.exercises ?? [] where exercise.measurement.supportsOneRepMax {
        if let value = OneRepMax.best(in: exercise.sets) { oneRepMaxes.append(value) }
    }
}
check("one-rep max estimates produced", !oneRepMaxes.isEmpty, "\(oneRepMaxes.count)")
if let maximum = oneRepMaxes.max() {
    check("one-rep max estimates are plausible", maximum < 500,
          String(format: "max %.1f kg", maximum))
}

// Set types. All four of Hevy's types appear in real data and all must map.
var setTypes = Set<StrengthSetType>()
for workout in mapped {
    for exercise in workout.strength?.exercises ?? [] {
        for set in exercise.sets { setTypes.insert(set.type) }
    }
}
check("no unknown set types", !setTypes.contains(.unknown),
      "types seen: \(setTypes.map(\.rawValue).sorted().joined(separator: ", "))")
print("Set types seen: \(setTypes.map(\.rawValue).sorted().joined(separator: ", "))")

// Warm-ups must be excluded from working volume, which is what makes the counts honest.
let allSets = mapped.flatMap { $0.strength?.exercises ?? [] }.flatMap(\.sets)
let warmups = allSets.filter { $0.type == .warmup }
if !warmups.isEmpty {
    check("warm-ups are excluded from working sets",
          warmups.allSatisfy { !$0.isWorkingSet },
          "\(warmups.count) warm-up sets")
    print("Warm-ups excluded: \(warmups.count)")
}

print("\n\(checks) checks")
if failures.isEmpty {
    print("HEVY PARSER VERIFIED AGAINST LIVE DATA")
    exit(0)
}
print("\n\(failures.count) FAILURES:")
for failure in failures { print(failure) }
exit(1)
