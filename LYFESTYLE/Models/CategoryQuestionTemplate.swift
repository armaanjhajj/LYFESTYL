//
//  CategoryQuestionTemplate.swift
//  LYFESTYL
//
//  The guided "help me organize this" flow. When the user picks a category from
//  the + menu, we ask a couple of short, tappable questions so the entry files
//  itself cleanly. These are STATIC by design: instant, deterministic, never a
//  hallucination, and they read as friendly organizing rather than AI analysis.
//  Every question is skippable; whatever the user answers becomes their own
//  `EntryField`s on the entry.
//

import Foundation

/// One step of the guided flow: a prompt with a few tappable options. The app
/// always appends its own "Something else" free-text affordance when
/// `allowsFreeText` is true, so options never need an "Other" entry.
struct GuidedQuestion: Identifiable, Hashable {
    /// Stable label stored as the `EntryField` label (kept short for the Log).
    let label: String
    /// The friendly question shown to the user.
    let prompt: String
    /// Concrete, mutually distinct tappable answers.
    let options: [String]
    /// Whether the user can type a free-text answer instead of tapping.
    var allowsFreeText: Bool = true
    /// When true, this answer also becomes the entry's `subtag` (e.g. SOCIAL "who").
    var feedsSubtag: Bool = false

    var id: String { label }
}

/// The ordered questions for one category.
struct CategoryQuestionTemplate {
    let category: InsightCategory
    let questions: [GuidedQuestion]

    /// The static template for a category. Two short questions each: the first
    /// names what is being logged, the second adds a little context.
    static func template(for category: InsightCategory) -> CategoryQuestionTemplate {
        switch category {
        case .nutrition:
            return .init(category: .nutrition, questions: [
                GuidedQuestion(label: "Logging",
                               prompt: "What are you logging?",
                               options: ["A meal", "A snack", "Hydration", "Supplements / meds", "How eating felt"]),
                GuidedQuestion(label: "When",
                               prompt: "When was this?",
                               options: ["Breakfast", "Lunch", "Dinner", "Throughout the day"])
            ])
        case .activity:
            return .init(category: .activity, questions: [
                GuidedQuestion(label: "Did",
                               prompt: "What did you do?",
                               options: ["A workout", "A walk or run", "A sport", "Everyday movement"]),
                GuidedQuestion(label: "Felt",
                               prompt: "How did it feel?",
                               options: ["Easy", "Moderate", "Hard", "Drained"])
            ])
        case .sleep:
            return .init(category: .sleep, questions: [
                GuidedQuestion(label: "Noting",
                               prompt: "What are you noting?",
                               options: ["Last night's sleep", "A nap", "Trouble sleeping", "How rested I feel"]),
                GuidedQuestion(label: "Felt",
                               prompt: "How do you feel?",
                               options: ["Rested", "Okay", "Tired", "Exhausted"])
            ])
        case .health:
            return .init(category: .health, questions: [
                GuidedQuestion(label: "Noting",
                               prompt: "What are you noting?",
                               options: ["A symptom", "Feeling unwell", "Feeling good", "An appointment or med"]),
                GuidedQuestion(label: "Status",
                               prompt: "Where is it at?",
                               options: ["New", "Ongoing", "Improving", "Resolved"])
            ])
        case .mind:
            return .init(category: .mind, questions: [
                GuidedQuestion(label: "About",
                               prompt: "What's on your mind?",
                               options: ["Mood", "Stress", "Focus", "A reflection"]),
                GuidedQuestion(label: "Right now",
                               prompt: "Right now you feel...",
                               options: ["Calm", "Mixed", "Low", "Overwhelmed"])
            ])
        case .social:
            return .init(category: .social, questions: [
                GuidedQuestion(label: "Who",
                               prompt: "Who was it with?",
                               options: ["Partner", "Family", "Friends", "Coworker"],
                               feedsSubtag: true),
                GuidedQuestion(label: "How it went",
                               prompt: "How did it go?",
                               options: ["Great", "Good", "Mixed", "Hard"])
            ])
        }
    }
}
