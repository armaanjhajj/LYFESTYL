//
//  MuscleBalance.swift
//  LYFESTYL
//
//  Pure aggregation for the STYL muscle-balance read: over a trailing window, how
//  much each muscle group and body system has been worked, and which regions have
//  gone light. Built entirely from the user's OWN logged workouts (measured sets,
//  never estimates), with muscle tags resolved from the on-device ExerciseLibrary.
//
//  Volume is a simple, honest weighting: each set of an exercise counts 1.0 toward
//  its PRIMARY muscles and 0.5 toward its ACCESSORY muscles. No scoring of the
//  person, only a neutral reflection of what they've trained (quiet-AI direction).
//  Kept UI-free so it's easy to reason about (mirrors Trends.swift).
//

import Foundation

/// Recent load for one muscle group.
struct MuscleGroupLoad: Identifiable, Hashable {
    let muscle: MuscleGroup
    let volume: Double
    let sets: Int
    var id: String { muscle.rawValue }
}

/// Recent load for one body system (the coarse region STYL surfaces).
struct BodySystemLoad: Identifiable, Hashable {
    let system: BodySystem
    let volume: Double
    /// Fraction of total recent volume (0 when nothing was trained).
    let share: Double
    let sets: Int
    let lastTrained: Date?
    /// Whole days since this region was last trained (nil if never, in window).
    let lastTrainedDaysAgo: Int?
    var id: String { system.rawValue }
    var wasTrained: Bool { volume > 0 }
}

struct MuscleBalance {
    let windowDays: Int
    /// All seven systems, sorted by display order, zero-filled so gaps are visible.
    let systemLoads: [BodySystemLoad]
    /// Muscle groups that got any work, most-worked first.
    let muscleLoads: [MuscleGroupLoad]
    /// Regions with no work in the window (what to prioritize next).
    let neglected: [BodySystem]

    var hasData: Bool { systemLoads.contains { $0.wasTrained } }

    init(entries: [JournalEntry], windowDays: Int = 7, now: Date = Date(), calendar: Calendar = .current) {
        self.windowDays = windowDays
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today

        let relevant = entries.filter { entry in
            entry.category == .activity
                && entry.workout != nil
                && calendar.startOfDay(for: entry.entryDate) >= start
        }

        var muscleVolume: [MuscleGroup: Double] = [:]
        var muscleSets: [MuscleGroup: Int] = [:]
        var systemVolume: [BodySystem: Double] = [:]
        var systemSets: [BodySystem: Int] = [:]
        var systemLast: [BodySystem: Date] = [:]

        for entry in relevant {
            guard let workout = entry.workout else { continue }
            let day = calendar.startOfDay(for: entry.entryDate)
            for logged in workout.exercises {
                guard let exercise = logged.exercise else { continue }
                let n = logged.effectiveSetCount
                var systemsHit = Set<BodySystem>()

                for muscle in exercise.primary {
                    muscleVolume[muscle, default: 0] += Double(n) * 1.0
                    muscleSets[muscle, default: 0] += n
                    systemVolume[muscle.system, default: 0] += Double(n) * 1.0
                    systemsHit.insert(muscle.system)
                }
                for muscle in exercise.secondary {
                    muscleVolume[muscle, default: 0] += Double(n) * 0.5
                    muscleSets[muscle, default: 0] += n
                    systemVolume[muscle.system, default: 0] += Double(n) * 0.5
                    systemsHit.insert(muscle.system)
                }
                for system in systemsHit {
                    systemSets[system, default: 0] += n
                    if let current = systemLast[system] {
                        if day > current { systemLast[system] = day }
                    } else {
                        systemLast[system] = day
                    }
                }
            }
        }

        let total = systemVolume.values.reduce(0, +)

        self.systemLoads = BodySystem.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { system in
                let volume = systemVolume[system] ?? 0
                let last = systemLast[system]
                let daysAgo = last.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 }
                return BodySystemLoad(
                    system: system,
                    volume: volume,
                    share: total > 0 ? volume / total : 0,
                    sets: systemSets[system] ?? 0,
                    lastTrained: last,
                    lastTrainedDaysAgo: daysAgo
                )
            }

        self.muscleLoads = muscleVolume
            .map { MuscleGroupLoad(muscle: $0.key, volume: $0.value, sets: muscleSets[$0.key] ?? 0) }
            .filter { $0.volume > 0 }
            .sorted { $0.volume > $1.volume }

        self.neglected = self.systemLoads.filter { !$0.wasTrained }.map(\.system)
    }

    /// A compact, plain-text summary for the on-device suggestion model. Neutral,
    /// factual, and explicit about what's been light so the suggestion can fill
    /// the gaps. No judgement, no numbers the user didn't log.
    func summaryForModel() -> String {
        var lines: [String] = ["What I have trained in the last \(windowDays) days:"]
        for load in systemLoads {
            let name = load.system.label.capitalized
            if load.wasTrained {
                let when: String
                switch load.lastTrainedDaysAgo {
                case 0: when = "today"
                case 1: when = "yesterday"
                case let d?: when = "\(d) days ago"
                default: when = "recently"
                }
                lines.append("- \(name): \(load.sets) set\(load.sets == 1 ? "" : "s"), last trained \(when)")
            } else {
                lines.append("- \(name): not trained")
            }
        }
        if !neglected.isEmpty {
            let names = neglected.map { $0.label.capitalized }
            lines.append("Least trained and worth prioritizing: \(names.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }
}
