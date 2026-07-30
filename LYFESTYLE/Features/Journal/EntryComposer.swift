//
//  EntryComposer.swift
//  LYFESTYL
//
//  The capture surface (CLAUDE.md §1): a single full-screen text field, keyboard
//  up immediately, zero structured fields. Voice is a full conversation now, not
//  inline dictation: tap the mic and you drop into a calm, on-device voice mode
//  (a reactive orb that listens, thinks, and talks a short follow-up back). What
//  you say there flows back into this draft, so you can review and save it like
//  any typed entry.
//
//  Keyboard behavior is deliberately native: the field is top-anchored so it's
//  always visible above the keyboard, tapping the empty area (or dragging) dismisses
//  it, and the voice control rides just above the keyboard via a safe-area inset,
//  so nothing shifts the surrounding layout.
//

import SwiftUI

struct EntryComposer: View {
    @Binding var text: String
    /// Set true once a voice conversation has fed into this draft, so the saved
    /// entry is stamped with the right source.
    @Binding var usedVoice: Bool
    /// The parent bumps this to request a save.
    @Binding var commitTrigger: Int
    /// Called when the parent should persist `text` and dismiss the composer.
    var onCommit: () -> Void

    @FocusState private var focused: Bool

    @State private var showVoice = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField(
                        "What's on your mind?",
                        text: $text,
                        prompt: Text("What's on your mind?").foregroundColor(.appTextMuted),
                        axis: .vertical
                    )
                    .font(.body.weight(.medium))
                    .foregroundStyle(.appTextEmphasis)
                    .tint(.appAccent)
                    .focused($focused)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    // Tap the empty space below the text to dismiss the keyboard.
                    Color.clear
                        .frame(minHeight: 360)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { voiceBar }
        .onAppear { focusSoon() }
        .onChange(of: commitTrigger) { _, _ in onCommit() }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceConversationView { spoken in
                applyVoice(spoken)
            }
        }
    }

    // MARK: - Voice entry point

    private var voiceBar: some View {
        HStack {
            Spacer()
            Button {
                focused = false
                showVoice = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.appAccent)
            .disabled(!SpeechService.isSupported)
            .accessibilityLabel("Start a voice conversation")
            Spacer()
        }
        .padding(.bottom, 10)
    }

    // MARK: - Actions

    private func applyVoice(_ spoken: String) {
        let addition = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        text = merged(base: text, addition: addition)
        usedVoice = true
        // Return focus so the user can tweak before saving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func merged(base: String, addition: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return addition }
        return trimmedBase + (trimmedBase.hasSuffix(" ") ? "" : " ") + addition
    }
}
