//
//  InsightEngine.swift
//  LYFESTYL
//
//  The on-device breakdown engine (CLAUDE.md §1). Wraps Apple's Foundation
//  Models framework: checks availability, runs each entry through a focused
//  `LanguageModelSession` with Guided Generation, and returns a typed
//  `EntryBreakdown` — fully offline, no key, no cost, nothing leaves the device.
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
    enum Availability: Equatable {
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
    enum EngineError: LocalizedError {
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
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
    }

    /// Break one entry's text into a typed `EntryBreakdown`. Each call uses a
    /// fresh session so entries are classified independently (no cross-entry
    /// context bleed, no context-window growth).
    func breakdown(of text: String) async throws -> EntryBreakdown {
        guard isAvailable else { throw EngineError.unavailable(availability) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EntryBreakdown(overallSummary: "", categories: [])
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let options = GenerationOptions(sampling: .greedy)

        do {
            let response = try await session.respond(
                to: Self.prompt(for: trimmed),
                generating: EntryBreakdown.self,
                options: options
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            // Re-check availability — the model may have gone away mid-flight.
            refreshAvailability()
            throw EngineError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt design (focused; the ~3B model excels at extraction)

    static let instructions = """
    You are the analysis engine for a health-journaling app. The user dumps a \
    short, casual, often vague note about their day — what they ate, how they \
    moved, how they slept, how they feel. Your job is to break that note into \
    structured, trackable insights.

    Rules:
    - Produce one insight for EACH of the four categories the note actually \
    touches: NUTRITION, ACTIVITY, SLEEP, HEALTH. Skip any category the note \
    doesn't mention. A note can produce several insights or just one.
    - Estimate tangible numbers when the category calls for them (calories and \
    macros for food, minutes and distance for exercise, hours for sleep). The \
    input is vague by design — make a reasonable, consistent estimate rather \
    than refusing. Leave a number nil only when there is genuinely nothing to \
    base it on.
    - Rank each category honestly with the provided scale and rubric. Be a fair, \
    consistent judge so the same kind of day always lands on the same rank.
    - Never invent specifics the user didn't say. Never give medical advice, \
    diagnoses, or warnings — just describe and estimate.
    - Keep summaries and details short and plain. No emojis, no preamble.
    """

    static func prompt(for text: String) -> String {
        """
        Break down this journal entry:

        \"\"\"
        \(text)
        \"\"\"
        """
    }
}
