//
//  CoachReply.swift
//  LYFESTYL
//
//  Guided Generation schema for one turn of the on-device AI coach chat. The model
//  answers in plain conversational prose (`message`) and, when it is actually
//  proposing a session, attaches a structured `workout` that the chat renders as a
//  real, loggable in-app component. Keeping the component inside the reply is what
//  lets the coach speak and hand you an actionable workout in the same breath.
//
//  Everything runs on-device via FoundationModels; nothing leaves the phone.
//

import FoundationModels

@Generable
struct CoachReply: Equatable {
    @Guide(description: "Your conversational reply to the user, in plain natural sentences. Warm, concise, and practical. Do not use markdown, headings, bullet characters, or em dashes.")
    var message: String

    @Guide(description: "A concrete workout to propose, but ONLY when the user is asking for a session or a specific plan clearly helps them. Leave it empty for ordinary conversation, questions, or acknowledgements.")
    var workout: WorkoutSuggestion?
}
