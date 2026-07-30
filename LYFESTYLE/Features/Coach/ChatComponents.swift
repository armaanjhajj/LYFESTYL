//
//  ChatComponents.swift
//  LYFESTYL
//
//  The building blocks of the AI coach chat: the user bubble, the assistant's
//  typewriter reveal, the thinking indicator, the inline (loggable) workout card,
//  the prompt chips, and the input bar. Clean, first-party, on-palette, so the
//  chat reads like a native surface of the app rather than a bolted-on bot.
//

import SwiftUI

// MARK: - User message

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Assistant message (typewriter reveal)

/// Reveals the assistant's text progressively, the calm "being written" feel.
/// Notices (errors, availability) render in a muted tone with a small glyph.
struct AssistantText: View {
    let text: String
    var isNotice: Bool = false
    /// Reveal with the typewriter animation (off for already-seen messages).
    var animated: Bool = true

    @State private var shown = ""
    @State private var revealing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isNotice {
                Image(systemName: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.appTextMuted)
                    .padding(.top, 3)
            }
            Text(shown)
                .font(.body)
                .foregroundStyle(isNotice ? .appTextMuted : .appTextEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .task(id: text) { await reveal() }
    }

    private func reveal() async {
        guard animated, !reduceMotion, !text.isEmpty else { shown = text; return }
        shown = ""
        revealing = true
        let characters = Array(text)
        var index = 0
        // Reveal a few characters per tick so long replies stay quick but readable.
        let step = max(1, characters.count / 140)
        while index < characters.count {
            index = min(characters.count, index + step)
            shown = String(characters[0..<index])
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { shown = text; return }
        }
        revealing = false
    }
}

// MARK: - Thinking indicator

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.appTextMuted)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityLabel("Thinking")
    }
}

// MARK: - Inline workout component

/// The coach's proposed session, rendered as a real, loggable app component right
/// inside the chat. Tapping Log files it as an ACTIVITY entry via `onLog`.
struct SuggestedWorkoutCard: View {
    let workout: WorkoutSuggestion
    let onLog: () -> Void

    @State private var logged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.appAccent)
                Text(workout.focus.uppercased())
                    .font(.footnote)
                    .fontWeight(.black)
                    .tracking(0.6)
                    .foregroundStyle(.appTextEmphasis)
            }

            VStack(spacing: 10) {
                ForEach(Array(workout.items.enumerated()), id: \.offset) { _, item in
                    itemRow(item)
                }
            }

            if !workout.note.isEmpty {
                Text(workout.note)
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                logged = true
                onLog()
            } label: {
                Label(logged ? "Added to your log" : "Log this session",
                      systemImage: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.appAccent)
            .disabled(logged)
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.18), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func itemRow(_ item: SuggestedItem) -> some View {
        let match = ExerciseLibrary.shared.match(name: item.name)
        let accent = match?.group.accent ?? .appAccentSecondary
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(accent).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(match?.name ?? item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                if let match {
                    Text(match.muscleSummary)
                        .font(.caption2)
                        .foregroundStyle(.appTextMuted)
                }
            }
            Spacer(minLength: 8)
            Text("\(item.sets) × \(item.reps)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.appTextEmphasis)
        }
    }
}

// MARK: - Prompt chips (empty state)

struct PromptChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.appTextEmphasis)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appSurface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Input bar

/// The Claude-style composer: a floating liquid-glass panel with the AI
/// disclaimer above it and the message field over a single functional action
/// (send). Attach / voice / model controls are intentionally omitted until they
/// are actually wired up.
struct ChatInputBar: View {
    @Binding var text: String
    var isResponding: Bool
    let onSend: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    var body: some View {
        VStack(spacing: 10) {
            disclaimer
            composer
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.caption2)
                .foregroundStyle(.appAccent)
            Text("Your coach is AI and can make mistakes. Double-check anything important.")
                .font(.caption2)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Message your coach", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .tint(.appAccent)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 6)
                .padding(.top, 4)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glassProminent)
                .tint(.appAccent)
                .clipShape(Circle())
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send")
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.appTextMuted.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { focused = true }
    }
}
