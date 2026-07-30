//
//  AIChatView.swift
//  LYFESTYL
//
//  The AI coach: a clean, native chat with the on-device model. You type, the reply
//  reveals as it's written, and when the coach proposes a session it arrives as a
//  real inline component you can log in one tap. Seeded with a private summary of
//  what you've trained recently, so "suggest a session" or "what should I do today"
//  come back grounded in your own log.
//
//  Everything is first-party and on-device (FoundationModels). Nothing leaves the
//  phone, and the chat degrades calmly when the model isn't available.
//

import SwiftUI

struct AIChatView: View {
    /// A plain-text summary of recent training, seeded into the coach's context.
    let contextSummary: String
    /// An optional first prompt sent automatically on open (e.g. from STYL).
    var initialPrompt: String? = nil

    @Environment(InsightEngine.self) private var engine
    @Environment(JournalStore.self) private var store
    @Environment(HealthDataStore.self) private var healthData
    @Environment(\.dismiss) private var dismiss

    @State private var chat: ChatConversation?
    @State private var draft = ""

    private let starters = [
        "Suggest a session for today",
        "What should I train next?",
        "Am I balanced lately?",
        "Give me a quick core finisher"
    ]

    var body: some View {
        NavigationStack {
            messages
                .background(Color.appBackground)
                .safeAreaInset(edge: .bottom) {
                    if let chat {
                        ChatInputBar(text: $draft, isResponding: chat.isResponding) { send() }
                    }
                }
                .navigationTitle("COACH")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await start() }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messages: some View {
        if let chat {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if chat.isEmpty {
                            greeting
                        }
                        ForEach(chat.messages) { message in
                            row(message, isLast: message.id == chat.messages.last?.id)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { scrollDown(proxy) }
                .onChange(of: chat.messages.last?.text) { scrollDown(proxy) }
                .onChange(of: chat.isResponding) { scrollDown(proxy) }
            }
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    private func row(_ message: ChatMessage, isLast: Bool) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text)
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if message.isThinking {
                    ThinkingIndicator()
                } else {
                    AssistantText(text: message.text, isNotice: message.isNotice, animated: isLast)
                    if let workout = message.workout, !workout.items.isEmpty {
                        SuggestedWorkoutCard(workout: workout) { log(workout) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.appAccent)
                Text("YOUR COACH")
                    .blackCaps(.subheadline, tracking: 0.8, color: .appTextEmphasis)
            }
            Text("Ask about your training, plan your next session, or see if you've been leaving anything out. Everything here runs privately on your device.")
                .font(.body)
                .foregroundStyle(.appTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(starters, id: \.self) { prompt in
                    PromptChip(text: prompt) { chat?.send(prompt) }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private let bottomID = "chat-bottom"

    private func start() async {
        guard chat == nil else { return }
        let conversation = ChatConversation(engine: engine, contextSummary: contextSummary)
        chat = conversation
        conversation.prewarm()
        if let initialPrompt {
            conversation.send(initialPrompt)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        chat?.send(text)
    }

    /// Log a suggested session into the unified training history, the same place a Hevy or
    /// hand-built session lands.
    private func log(_ workout: WorkoutSuggestion) {
        let exercises: [StrengthExercise] = workout.items.enumerated().map { index, item in
            let match = ExerciseLibrary.shared.match(name: item.name)
            let count = max(item.sets, 1)
            let sets = (0..<count).map { StrengthSet(index: $0, reps: item.reps) }
            return StrengthExercise(
                index: index,
                name: match?.name ?? item.name,
                libraryExerciseID: match?.id,
                measurement: .weightReps,
                primaryTargets: (match?.primary ?? []).map { MuscleTarget.muscle($0) },
                secondaryTargets: (match?.secondary ?? []).map { MuscleTarget.muscle($0) },
                equipment: match?.equipment ?? .other,
                sets: sets
            )
        }
        Task {
            await healthData.logManualWorkout(
                title: nil, notes: nil, durationSeconds: nil,
                strength: StrengthSession(exercises: exercises)
            )
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}
