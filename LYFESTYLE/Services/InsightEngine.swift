//
//  InsightEngine.swift
//  LYFESTYL
//
//  The on-device breakdown engine (CLAUDE.md §1). Wraps Apple's Foundation
//  Models framework: checks availability, runs each entry through a focused
//  `LanguageModelSession` with Guided Generation, and returns a typed
//  `EntryBreakdown`, fully offline, no key, no cost, nothing leaves the device.
//
//  Determinism: we sample greedily so the same entry yields stable estimates,
//  which is what makes LYFESTYL's trends comparable over time.
//

import Foundation
import FoundationModels
import Observation

@MainActor
@Observable
final class InsightEngine {

    /// User-facing availability of the on-device model.
    nonisolated enum Availability: Equatable {
        case available
        case downloading
        case appleIntelligenceOff
        case deviceNotEligible
        case unknown

        /// Whether a breakdown can run right now.
        var canRun: Bool { self == .available }

        var title: String {
            switch self {
            case .available:            "On-device analysis ready"
            case .downloading:          "Model downloading"
            case .appleIntelligenceOff: "Apple Intelligence is off"
            case .deviceNotEligible:    "Not available on this device"
            case .unknown:              "Analysis unavailable"
            }
        }

        /// Calm, non-alarming explanation. Always reassures that entries are safe.
        var message: String {
            switch self {
            case .available:
                "Your entries are broken down privately on your device."
            case .downloading:
                "Apple Intelligence is still downloading the on-device model. Your entries are saved and will be analyzed automatically once it's ready."
            case .appleIntelligenceOff:
                "Turn on Apple Intelligence in Settings to enable private, on-device breakdowns. Your entries are saved in the meantime."
            case .deviceNotEligible:
                "This device doesn't support Apple Intelligence, so on-device breakdowns aren't available. Your entries are still saved and searchable."
            case .unknown:
                "On-device analysis is unavailable right now. Your entries are saved and will be analyzed when it returns."
            }
        }

        var symbolName: String {
            switch self {
            case .available:            "checkmark.seal.fill"
            case .downloading:          "arrow.down.circle.fill"
            case .appleIntelligenceOff: "gearshape.fill"
            case .deviceNotEligible:    "exclamationmark.triangle.fill"
            case .unknown:              "questionmark.circle.fill"
            }
        }
    }

    private(set) var availability: Availability = .unknown

    private let model = SystemLanguageModel.default

    init() {
        refreshAvailability()
    }

    /// Re-read the system model's availability (call on launch and foreground).
    func refreshAvailability() {
        availability = Self.map(model.availability)
    }

    var isAvailable: Bool { availability.canRun }

    private static func map(_ availability: SystemLanguageModel.Availability) -> Availability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .modelNotReady:               return .downloading
            case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
            case .deviceNotEligible:           return .deviceNotEligible
            @unknown default:                  return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    /// Errors surfaced to the queue/UI. The raw entry is never lost regardless.
    nonisolated enum EngineError: LocalizedError {
        case unavailable(Availability)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let a): a.message
            case .generationFailed(let m): m
            }
        }
    }

    /// Reduce first-run latency by warming the model. Safe to call repeatedly.
    func prewarm() {
        guard isAvailable else { return }
        let session = LanguageModelSession(instructions: Self.classifyInstructions)
        session.prewarm()
    }

    // MARK: - Classification (the only behind-the-scenes job)

    /// Quietly file a free-written entry under ONE category and give it a clean
    /// title. No ranking, no judgment, no estimated numbers. Each call uses a
    /// fresh session so entries are classified independently. The caller maps a
    /// `"NONE"` category to nil (a free thought with nothing trackable).
    func classify(_ text: String) async throws -> EntryClassification {
        guard isAvailable else { throw EngineError.unavailable(availability) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EntryClassification(category: "NONE", title: "", subtag: nil)
        }

        let session = LanguageModelSession(instructions: Self.classifyInstructions)
        let options = GenerationOptions(sampling: .greedy)

        do {
            let response = try await session.respond(
                to: Self.classifyPrompt(for: trimmed),
                generating: EntryClassification.self,
                options: options
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            refreshAvailability()
            throw EngineError.generationFailed(error.localizedDescription)
        }
    }

    static let classifyInstructions = """
    You help a personal life-journaling app quietly organize what someone logs. \
    The user writes a short, casual note about their day. Your only job is to file \
    it under the ONE lifestyle category it is most about, and give it a short, \
    clean title in their own voice.

    You do NOT judge, rate, score, or grade anything. You do NOT estimate numbers \
    (no calories, no hours, no minutes). You do NOT give advice, diagnoses, or \
    warnings. You only sort and title.

    Categories: NUTRITION (food and drink), ACTIVITY (exercise and movement), \
    SLEEP (how they slept), HEALTH (physical health, symptoms, illness, meds), \
    MIND (mood, stress, focus, reflection), SOCIAL (time with family, friends, or \
    a partner). If the note is a stray thought, a quote, a to-do, or a joke with \
    nothing trackable, the category is NONE. When a note touches more than one \
    area, pick the single one it is most about.

    The title is 3 to 6 plain words, neutral, no preamble, no 'The user', no \
    rating words, no emojis, no em dashes. For SOCIAL, set the subtag to the \
    specific relationship (e.g. 'partner', 'mother', 'coworker'); leave subtag \
    empty for every other category.
    """

    static func classifyPrompt(for text: String) -> String {
        """
        File this journal entry:

        \"\"\"
        \(text)
        \"\"\"
        """
    }

    // MARK: - Workout parsing (free-write ACTIVITY → structured movements)

    /// Turn a free-written workout note into `LoggedExercise`s, resolved against
    /// the on-device `ExerciseLibrary` so every parsed movement carries real
    /// muscle tags. Movements the library can't match are still kept (as custom
    /// entries) so the logged session faithfully mirrors what the user wrote.
    /// Returns an empty array when the note isn't a workout, or when the model is
    /// unavailable (the raw note is always preserved by the caller).
    func parseWorkout(_ text: String) async throws -> [LoggedExercise] {
        guard isAvailable else { throw EngineError.unavailable(availability) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let session = LanguageModelSession(instructions: Self.parseInstructions)
        let options = GenerationOptions(sampling: .greedy)
        do {
            let response = try await session.respond(
                to: Self.parsePrompt(for: trimmed),
                generating: ParsedWorkout.self,
                options: options
            )
            return response.content.exercises.compactMap { Self.resolve($0) }
        } catch let error as LanguageModelSession.GenerationError {
            refreshAvailability()
            throw EngineError.generationFailed(error.localizedDescription)
        }
    }

    /// Map one parsed movement onto a `LoggedExercise`. Builds the requested
    /// number of sets (default one) carrying any reps/weight the note specified.
    private static func resolve(_ parsed: ParsedExercise) -> LoggedExercise? {
        let name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let matched = ExerciseLibrary.shared.match(name: name)
        let count = max(parsed.sets ?? 1, 1)
        let sets = (0..<count).map { _ in
            ExerciseSet(reps: parsed.reps, weight: parsed.weight)
        }
        return LoggedExercise(
            exerciseID: matched?.id ?? "",
            name: matched?.name ?? name,
            sets: sets
        )
    }

    static let parseInstructions = """
    You extract the exercises from a short, casual note about a workout so a \
    fitness app can log them. Return each distinct movement the person did, using \
    its common gym name (e.g. 'Barbell Bench Press', 'Incline Dumbbell Press', \
    'Lat Pulldown', 'Barbell Back Squat', 'Running').

    If the note names a session type but not the movements (e.g. 'push day', 'leg \
    day', 'chest and tris'), infer the specific exercises a lifter would typically \
    do for it. Capture sets, reps, and weight ONLY when the note states them; never \
    invent numbers. If the note is not about exercise at all, return no exercises. \
    Do not judge, rate, or comment. No em dashes.
    """

    static func parsePrompt(for text: String) -> String {
        """
        Extract the workout from this note:

        \"\"\"
        \(text)
        \"\"\"
        """
    }

    // Workout suggestions now happen conversationally in the AI coach chat, which
    // drives the model directly via `CoachReply` (see ChatConversation). The
    // `WorkoutSuggestion` schema it produces is reused as the inline card there.
}
