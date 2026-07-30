//
//  ChatConversation.swift
//  LYFESTYL
//
//  Drives the on-device AI coach chat. Wraps a single `LanguageModelSession`, which
//  keeps the whole conversation transcript itself, so each turn is context-aware
//  across the session. Every reply is a `CoachReply` (prose plus an optional inline
//  workout), generated privately on-device.
//
//  Failures are surfaced, not swallowed: if the model is unavailable or a turn
//  errors, the chat shows a clear, calm system message with the real reason (this
//  is what makes the AI feel reliable instead of silently doing nothing).
//

import Foundation
import Observation
import FoundationModels

/// One message in the coach chat.
struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }

    let id: UUID
    var role: Role
    var text: String
    /// An inline, loggable workout the coach attached to this reply.
    var workout: WorkoutSuggestion?
    /// The assistant is still generating this turn (drives the thinking dots).
    var isThinking: Bool
    /// A calm error/notice rather than a normal reply (styled differently).
    var isNotice: Bool

    init(id: UUID = UUID(), role: Role, text: String = "",
         workout: WorkoutSuggestion? = nil, isThinking: Bool = false, isNotice: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.workout = workout
        self.isThinking = isThinking
        self.isNotice = isNotice
    }
}

@MainActor
@Observable
final class ChatConversation {
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false

    private let engine: InsightEngine
    private let session: LanguageModelSession

    init(engine: InsightEngine, contextSummary: String) {
        self.engine = engine
        self.session = LanguageModelSession(instructions: Self.instructions(context: contextSummary))
    }

    /// Warm the model so the first reply comes back fast. Safe to call repeatedly.
    func prewarm() {
        guard engine.isAvailable else { return }
        session.prewarm()
    }

    var isEmpty: Bool { messages.isEmpty }

    /// Send a user turn and generate the coach's reply. No-ops on empty input or
    /// while a turn is already in flight (the session can't answer concurrently).
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: text))

        engine.refreshAvailability()
        guard engine.isAvailable else {
            messages.append(ChatMessage(
                role: .assistant,
                text: engine.availability.message,
                isNotice: true
            ))
            return
        }

        let placeholder = ChatMessage(role: .assistant, isThinking: true)
        messages.append(placeholder)
        let id = placeholder.id
        isResponding = true

        Task {
            do {
                let response = try await session.respond(
                    to: text,
                    generating: CoachReply.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                apply(id: id, text: response.content.message, workout: response.content.workout)
            } catch {
                // The model refused, is still preparing its assets, or the turn was
                // interrupted. Keep it calm and recoverable; the transcript is intact
                // for the next try, and nothing the user logged is affected.
                engine.refreshAvailability()
                apply(id: id, text: "I couldn't generate that just now. The on-device model may still be getting ready. Give it a moment and try again.", isNotice: true)
            }
            isResponding = false
        }
    }

    private func apply(id: UUID, text: String, workout: WorkoutSuggestion? = nil, isNotice: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        messages[index].text = clean.isEmpty ? "Here you go." : clean
        messages[index].workout = workout
        messages[index].isThinking = false
        messages[index].isNotice = isNotice
    }

    // MARK: - Copy

    private static func instructions(context: String) -> String {
        """
        You are the training coach inside LYFESTYL, a calm, private personal health \
        app. You help the user plan workouts, understand their recent training, and \
        stay balanced. You are warm, concise, and practical, like a knowledgeable \
        friend, not a hype machine.

        Here is a summary of what the user has trained recently, built from their own \
        logged workouts:

        \(context)

        When the user asks for a workout, or when a concrete session clearly helps, \
        attach a structured workout: a short focus, 3 to 6 exercises with sensible \
        sets and reps, and one calm sentence of context. Favor the areas that have \
        been trained least. Use standard gym exercise names so the app recognizes \
        them. For ordinary questions or chat, reply in plain sentences and leave the \
        workout empty.

        Never judge, shame, grade, or rank the user. Never estimate their calories, \
        weight, or fitness level. Do not use markdown, headings, bullet characters, \
        or em dashes. Keep replies short unless asked for detail.
        """
    }
}
