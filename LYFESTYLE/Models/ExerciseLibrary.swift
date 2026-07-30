//
//  ExerciseLibrary.swift
//  LYFESTYL
//
//  The catalog behind the ACTIVITY logger, the "vast list of every movement"
//  (barbell vs. dumbbell chest press, and everything else). It's a static,
//  on-device database, so search is instant, offline, and never hallucinated.
//
//  Each entry declares its muscles (<=2 primary, <=2 accessory) which is the
//  ground truth for the STYL muscle-balance read. Add movements freely; ids are
//  stable slugs and must stay unique (persisted on logged entries).
//
//  This is also the closed vocabulary the on-device model maps free-written
//  workouts onto (see `match(name:)`), so the parsed data always resolves to a
//  real, muscle-tagged exercise.
//

import Foundation

nonisolated final class ExerciseLibrary {
    static let shared = ExerciseLibrary()

    /// Every movement, in catalog order.
    let all: [Exercise]

    private let byID: [String: Exercise]

    private init() {
        let all = ExerciseLibrary.catalog
        self.all = all
        self.byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Lookup

    func exercise(id: String) -> Exercise? { byID[id] }

    /// Movements filed under a body system, for the grouped browse view.
    func exercises(in system: BodySystem) -> [Exercise] {
        all.filter { $0.group == system }
    }

    /// Token-AND search across name, equipment and muscles. Empty query returns
    /// everything (catalog order). Ranks exact/prefix name hits first.
    func search(_ query: String) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        let tokens = q.split(separator: " ").map(String.init)
        let hits = all.filter { ex in
            let hay = ex.searchHaystack
            return tokens.allSatisfy { hay.contains($0) }
        }
        return hits.sorted { a, b in
            rank(a, query: q) < rank(b, query: q)
        }
    }

    private func rank(_ ex: Exercise, query: String) -> Int {
        let name = ex.name.lowercased()
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains(query) { return 2 }
        return 3
    }

    // MARK: - Fuzzy name matching (for the on-device free-write parser)

    /// Best-effort resolve a model-produced movement name to a real library
    /// entry. Tries exact, then substring, then token-overlap scoring so
    /// "chest press" or "flat bench" still land on something sensible. Returns
    /// nil when nothing clears a minimum overlap (caller keeps it as raw text).
    func match(name raw: String) -> Exercise? {
        let query = Self.normalize(raw)
        guard !query.isEmpty else { return nil }

        if let exact = all.first(where: { Self.normalize($0.name) == query }) {
            return exact
        }
        let queryTokens = Set(query.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return nil }

        var best: (ex: Exercise, score: Double)?
        for ex in all {
            let nameTokens = Set(Self.normalize(ex.name).split(separator: " ").map(String.init))
            let overlap = Double(queryTokens.intersection(nameTokens).count)
            guard overlap > 0 else { continue }
            // Reward covering the movement's own name (so "press" alone stays weak)
            // and covering the query. Bias toward more specific (longer) matches.
            let score = overlap / Double(nameTokens.count) + overlap / Double(queryTokens.count)
            if best == nil || score > best!.score { best = (ex, score) }
        }
        // Require a meaningful match (a shared movement word plus context).
        guard let best, best.score >= 0.75 else { return nil }
        return best.ex
    }

    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let stripped = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        // Drop noise words that don't disambiguate a movement.
        let noise: Set<String> = ["the", "a", "an", "of", "with", "some", "few", "reps", "sets", "set", "rep", "did", "do", "and", "for", "on", "my", "to"]
        return String(stripped)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !noise.contains($0) }
            .joined(separator: " ")
    }
}

// MARK: - The catalog

nonisolated extension ExerciseLibrary {
    static let catalog: [Exercise] = chest + back + shoulders + arms + legs + core + cardio + fullBody

    // Convenience so the big list reads cleanly.
    private static func ex(_ id: String, _ name: String, _ equip: Equipment,
                           _ primary: [MuscleGroup], _ secondary: [MuscleGroup] = []) -> Exercise {
        Exercise(id, name, equip, primary: primary, secondary: secondary)
    }

    // MARK: Chest
    private static let chest: [Exercise] = [
        ex("barbell-bench-press", "Barbell Bench Press", .barbell, [.chest], [.triceps, .frontDelts]),
        ex("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, [.chest], [.frontDelts, .triceps]),
        ex("decline-barbell-bench-press", "Decline Barbell Bench Press", .barbell, [.chest], [.triceps]),
        ex("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, [.chest], [.triceps, .frontDelts]),
        ex("incline-dumbbell-press", "Incline Dumbbell Press", .dumbbell, [.chest], [.frontDelts, .triceps]),
        ex("decline-dumbbell-press", "Decline Dumbbell Press", .dumbbell, [.chest], [.triceps]),
        ex("dumbbell-fly", "Dumbbell Fly", .dumbbell, [.chest], [.frontDelts]),
        ex("incline-dumbbell-fly", "Incline Dumbbell Fly", .dumbbell, [.chest], [.frontDelts]),
        ex("cable-fly", "Cable Fly", .cable, [.chest], [.frontDelts]),
        ex("low-cable-fly", "Low Cable Fly", .cable, [.chest], [.frontDelts]),
        ex("high-cable-fly", "High Cable Fly", .cable, [.chest], [.frontDelts]),
        ex("cable-crossover", "Cable Crossover", .cable, [.chest], [.frontDelts]),
        ex("pec-deck", "Pec Deck", .machine, [.chest], [.frontDelts]),
        ex("machine-chest-press", "Machine Chest Press", .machine, [.chest], [.triceps]),
        ex("incline-machine-press", "Incline Machine Press", .machine, [.chest], [.frontDelts]),
        ex("smith-machine-bench-press", "Smith Machine Bench Press", .machine, [.chest], [.triceps]),
        ex("push-up", "Push-Up", .bodyweight, [.chest], [.triceps, .frontDelts]),
        ex("incline-push-up", "Incline Push-Up", .bodyweight, [.chest], [.triceps]),
        ex("decline-push-up", "Decline Push-Up", .bodyweight, [.chest], [.frontDelts]),
        ex("diamond-push-up", "Diamond Push-Up", .bodyweight, [.triceps], [.chest]),
        ex("chest-dip", "Chest Dip", .bodyweight, [.chest], [.triceps]),
        ex("landmine-press", "Landmine Press", .barbell, [.chest, .frontDelts], [.triceps]),
        ex("svend-press", "Svend Press", .other, [.chest], [.frontDelts]),
        ex("dumbbell-pullover", "Dumbbell Pullover", .dumbbell, [.chest, .lats], [.triceps]),
    ]

    // MARK: Back
    private static let back: [Exercise] = [
        ex("barbell-deadlift", "Barbell Deadlift", .barbell, [.lowerBack, .hamstrings], [.glutes, .traps]),
        ex("rack-pull", "Rack Pull", .barbell, [.traps, .lowerBack], [.glutes]),
        ex("pull-up", "Pull-Up", .bodyweight, [.lats], [.biceps, .upperBack]),
        ex("chin-up", "Chin-Up", .bodyweight, [.lats, .biceps], [.upperBack]),
        ex("wide-grip-pull-up", "Wide-Grip Pull-Up", .bodyweight, [.lats], [.upperBack]),
        ex("lat-pulldown", "Lat Pulldown", .cable, [.lats], [.biceps, .upperBack]),
        ex("close-grip-pulldown", "Close-Grip Pulldown", .cable, [.lats], [.biceps]),
        ex("wide-grip-pulldown", "Wide-Grip Pulldown", .cable, [.lats], [.upperBack]),
        ex("straight-arm-pulldown", "Straight-Arm Pulldown", .cable, [.lats], [.triceps]),
        ex("bent-over-barbell-row", "Bent-Over Barbell Row", .barbell, [.lats, .upperBack], [.biceps, .rearDelts]),
        ex("pendlay-row", "Pendlay Row", .barbell, [.upperBack, .lats], [.biceps]),
        ex("one-arm-dumbbell-row", "One-Arm Dumbbell Row", .dumbbell, [.lats], [.upperBack, .biceps]),
        ex("seated-cable-row", "Seated Cable Row", .cable, [.upperBack, .lats], [.biceps]),
        ex("t-bar-row", "T-Bar Row", .barbell, [.upperBack, .lats], [.biceps]),
        ex("chest-supported-row", "Chest-Supported Row", .machine, [.upperBack], [.lats, .rearDelts]),
        ex("machine-row", "Machine Row", .machine, [.upperBack, .lats], [.biceps]),
        ex("meadows-row", "Meadows Row", .barbell, [.lats, .upperBack], [.biceps]),
        ex("inverted-row", "Inverted Row", .bodyweight, [.upperBack], [.lats, .biceps]),
        ex("barbell-shrug", "Barbell Shrug", .barbell, [.traps], [.forearms]),
        ex("dumbbell-shrug", "Dumbbell Shrug", .dumbbell, [.traps], [.forearms]),
        ex("back-extension", "Back Extension", .bodyweight, [.lowerBack], [.glutes, .hamstrings]),
        ex("good-morning", "Good Morning", .barbell, [.hamstrings, .lowerBack], [.glutes]),
    ]

    // MARK: Shoulders
    private static let shoulders: [Exercise] = [
        ex("barbell-overhead-press", "Barbell Overhead Press", .barbell, [.frontDelts], [.sideDelts, .triceps]),
        ex("seated-dumbbell-press", "Seated Dumbbell Press", .dumbbell, [.frontDelts], [.sideDelts, .triceps]),
        ex("arnold-press", "Arnold Press", .dumbbell, [.frontDelts, .sideDelts], [.triceps]),
        ex("machine-shoulder-press", "Machine Shoulder Press", .machine, [.frontDelts], [.triceps]),
        ex("push-press", "Push Press", .barbell, [.frontDelts], [.triceps, .quads]),
        ex("behind-neck-press", "Behind-the-Neck Press", .barbell, [.sideDelts, .frontDelts], [.triceps]),
        ex("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, [.sideDelts], [.traps]),
        ex("cable-lateral-raise", "Cable Lateral Raise", .cable, [.sideDelts], [.traps]),
        ex("machine-lateral-raise", "Machine Lateral Raise", .machine, [.sideDelts], [.traps]),
        ex("front-raise", "Front Raise", .dumbbell, [.frontDelts], [.chest]),
        ex("rear-delt-fly", "Rear Delt Fly", .dumbbell, [.rearDelts], [.upperBack]),
        ex("reverse-pec-deck", "Reverse Pec Deck", .machine, [.rearDelts], [.upperBack]),
        ex("face-pull", "Face Pull", .cable, [.rearDelts], [.upperBack, .traps]),
        ex("upright-row", "Upright Row", .barbell, [.sideDelts, .traps], [.biceps]),
    ]

    // MARK: Arms
    private static let arms: [Exercise] = [
        // Biceps
        ex("barbell-curl", "Barbell Curl", .barbell, [.biceps], [.forearms]),
        ex("ez-bar-curl", "EZ-Bar Curl", .barbell, [.biceps], [.forearms]),
        ex("dumbbell-curl", "Dumbbell Curl", .dumbbell, [.biceps], [.forearms]),
        ex("hammer-curl", "Hammer Curl", .dumbbell, [.biceps, .forearms]),
        ex("incline-dumbbell-curl", "Incline Dumbbell Curl", .dumbbell, [.biceps]),
        ex("preacher-curl", "Preacher Curl", .barbell, [.biceps]),
        ex("concentration-curl", "Concentration Curl", .dumbbell, [.biceps]),
        ex("cable-curl", "Cable Curl", .cable, [.biceps]),
        ex("spider-curl", "Spider Curl", .dumbbell, [.biceps]),
        ex("machine-preacher-curl", "Machine Preacher Curl", .machine, [.biceps]),
        // Triceps
        ex("close-grip-bench-press", "Close-Grip Bench Press", .barbell, [.triceps], [.chest]),
        ex("triceps-pushdown", "Triceps Pushdown", .cable, [.triceps]),
        ex("rope-pushdown", "Rope Pushdown", .cable, [.triceps]),
        ex("overhead-triceps-extension", "Overhead Triceps Extension", .dumbbell, [.triceps]),
        ex("skull-crusher", "Skull Crusher", .barbell, [.triceps]),
        ex("dumbbell-kickback", "Dumbbell Kickback", .dumbbell, [.triceps]),
        ex("triceps-dip", "Triceps Dip", .bodyweight, [.triceps], [.chest]),
        ex("bench-dip", "Bench Dip", .bodyweight, [.triceps]),
        // Forearms
        ex("wrist-curl", "Wrist Curl", .dumbbell, [.forearms]),
        ex("reverse-wrist-curl", "Reverse Wrist Curl", .dumbbell, [.forearms]),
        ex("reverse-curl", "Reverse Curl", .barbell, [.forearms, .biceps]),
        ex("farmers-carry", "Farmer's Carry", .dumbbell, [.forearms, .traps], [.abs]),
    ]

    // MARK: Legs
    private static let legs: [Exercise] = [
        ex("barbell-back-squat", "Barbell Back Squat", .barbell, [.quads, .glutes], [.hamstrings, .lowerBack]),
        ex("front-squat", "Front Squat", .barbell, [.quads], [.glutes, .abs]),
        ex("goblet-squat", "Goblet Squat", .dumbbell, [.quads, .glutes]),
        ex("hack-squat", "Hack Squat", .machine, [.quads], [.glutes]),
        ex("leg-press", "Leg Press", .machine, [.quads, .glutes], [.hamstrings]),
        ex("bulgarian-split-squat", "Bulgarian Split Squat", .dumbbell, [.quads, .glutes], [.hamstrings]),
        ex("walking-lunge", "Walking Lunge", .dumbbell, [.quads, .glutes], [.hamstrings]),
        ex("reverse-lunge", "Reverse Lunge", .dumbbell, [.glutes, .quads], [.hamstrings]),
        ex("step-up", "Step-Up", .dumbbell, [.quads, .glutes]),
        ex("pistol-squat", "Pistol Squat", .bodyweight, [.quads, .glutes]),
        ex("sissy-squat", "Sissy Squat", .bodyweight, [.quads]),
        ex("leg-extension", "Leg Extension", .machine, [.quads]),
        ex("romanian-deadlift", "Romanian Deadlift", .barbell, [.hamstrings, .glutes], [.lowerBack]),
        ex("sumo-deadlift", "Sumo Deadlift", .barbell, [.glutes, .hamstrings], [.lowerBack, .quads]),
        ex("seated-leg-curl", "Seated Leg Curl", .machine, [.hamstrings]),
        ex("lying-leg-curl", "Lying Leg Curl", .machine, [.hamstrings]),
        ex("nordic-curl", "Nordic Curl", .bodyweight, [.hamstrings]),
        ex("hip-thrust", "Hip Thrust", .barbell, [.glutes], [.hamstrings]),
        ex("glute-bridge", "Glute Bridge", .bodyweight, [.glutes], [.hamstrings]),
        ex("cable-kickback", "Cable Glute Kickback", .cable, [.glutes]),
        ex("standing-calf-raise", "Standing Calf Raise", .machine, [.calves]),
        ex("seated-calf-raise", "Seated Calf Raise", .machine, [.calves]),
        ex("leg-press-calf-raise", "Leg Press Calf Raise", .machine, [.calves]),
        ex("hip-adduction", "Hip Adduction", .machine, [.adductors]),
        ex("hip-abduction", "Hip Abduction", .machine, [.abductors, .glutes]),
    ]

    // MARK: Core
    private static let core: [Exercise] = [
        ex("plank", "Plank", .bodyweight, [.abs], [.obliques]),
        ex("side-plank", "Side Plank", .bodyweight, [.obliques], [.abs]),
        ex("crunch", "Crunch", .bodyweight, [.abs]),
        ex("sit-up", "Sit-Up", .bodyweight, [.abs], [.obliques]),
        ex("hanging-leg-raise", "Hanging Leg Raise", .bodyweight, [.abs], [.obliques]),
        ex("lying-leg-raise", "Lying Leg Raise", .bodyweight, [.abs]),
        ex("cable-crunch", "Cable Crunch", .cable, [.abs]),
        ex("russian-twist", "Russian Twist", .bodyweight, [.obliques], [.abs]),
        ex("bicycle-crunch", "Bicycle Crunch", .bodyweight, [.abs, .obliques]),
        ex("mountain-climber", "Mountain Climber", .bodyweight, [.abs], [.cardio]),
        ex("ab-wheel-rollout", "Ab Wheel Rollout", .other, [.abs], [.obliques]),
        ex("dead-bug", "Dead Bug", .bodyweight, [.abs]),
        ex("hollow-hold", "Hollow Hold", .bodyweight, [.abs]),
        ex("cable-woodchopper", "Cable Woodchopper", .cable, [.obliques], [.abs]),
        ex("flutter-kick", "Flutter Kick", .bodyweight, [.abs]),
        ex("v-up", "V-Up", .bodyweight, [.abs]),
        ex("toes-to-bar", "Toes-to-Bar", .bodyweight, [.abs], [.lats]),
    ]

    // MARK: Cardio / conditioning
    private static let cardio: [Exercise] = [
        ex("running", "Running", .cardio, [.cardio], [.quads]),
        ex("treadmill", "Treadmill", .cardio, [.cardio], [.quads]),
        ex("outdoor-cycling", "Cycling", .cardio, [.cardio], [.quads]),
        ex("stationary-bike", "Stationary Bike", .cardio, [.cardio], [.quads]),
        ex("rowing-machine", "Rowing Machine", .cardio, [.cardio], [.upperBack, .lats]),
        ex("elliptical", "Elliptical", .cardio, [.cardio]),
        ex("stair-climber", "Stair Climber", .cardio, [.cardio], [.glutes]),
        ex("jump-rope", "Jump Rope", .cardio, [.cardio], [.calves]),
        ex("swimming", "Swimming", .cardio, [.cardio], [.lats]),
        ex("hiking", "Hiking", .cardio, [.cardio], [.quads]),
        ex("walking", "Walking", .cardio, [.cardio]),
        ex("incline-walk", "Incline Walk", .cardio, [.cardio], [.glutes]),
        ex("assault-bike", "Assault Bike", .cardio, [.cardio], [.quads]),
        ex("sprints", "Sprints", .cardio, [.cardio, .hamstrings], [.glutes]),
        ex("battle-ropes", "Battle Ropes", .cardio, [.cardio], [.frontDelts]),
        ex("ski-erg", "Ski Erg", .cardio, [.cardio], [.lats]),
        ex("box-jump", "Box Jump", .bodyweight, [.quads, .glutes], [.calves]),
        ex("burpee", "Burpee", .bodyweight, [.cardio], [.chest, .quads]),
    ]

    // MARK: Full-body / Olympic
    private static let fullBody: [Exercise] = [
        ex("clean-and-jerk", "Clean and Jerk", .barbell, [.quads, .frontDelts], [.glutes, .traps]),
        ex("power-clean", "Power Clean", .barbell, [.quads, .traps], [.glutes, .hamstrings]),
        ex("snatch", "Snatch", .barbell, [.quads, .sideDelts], [.glutes, .traps]),
        ex("clean-and-press", "Clean and Press", .barbell, [.frontDelts, .quads], [.traps]),
        ex("kettlebell-swing", "Kettlebell Swing", .kettlebell, [.glutes, .hamstrings], [.lowerBack, .cardio]),
        ex("thruster", "Thruster", .barbell, [.quads, .frontDelts], [.glutes, .triceps]),
        ex("wall-ball", "Wall Ball", .other, [.quads, .frontDelts], [.glutes]),
        ex("turkish-get-up", "Turkish Get-Up", .kettlebell, [.abs, .frontDelts], [.glutes]),
        ex("man-maker", "Man Maker", .dumbbell, [.chest, .quads], [.cardio]),
    ]
}
