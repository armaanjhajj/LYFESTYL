//
//  VoiceConversationView.swift
//  LYFESTYL
//
//  Full-screen voice mode. The orb is the centerpiece: it breathes while idle and
//  pulses with your voice while it listens. You talk like a voice memo, the live
//  transcript builds beneath the orb, and tapping Done drops the text into the
//  draft so it flows through the same pipeline as a typed entry. Entirely
//  on-device.
//

import SwiftUI

struct VoiceConversationView: View {
    /// Receives the transcript when the user finishes with something to save.
    var onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var convo = VoiceConversation()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                VoiceOrb(level: convo.speech.inputLevel, phase: convo.phase)
                Text(convo.phase.caption)
                    .blackCaps(.subheadline, tracking: 1.5, color: .appTextMuted)
                    .padding(.top, 18)
                    .contentTransition(.opacity)
                Spacer(minLength: 12)
                transcript
                Spacer(minLength: 12)
                controls
            }
            .padding(.horizontal, 24)

            if let error = convo.errorMessage {
                errorOverlay(error)
            }
        }
        .interactiveDismissDisabled()
        .task {
            convo.onComplete = { text in
                onComplete(text)
                dismiss()
            }
            convo.onCancel = { dismiss() }
            convo.start()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { convo.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
                    .frame(width: 40, height: 40)
                    .background(Color.appSurface, in: Circle())
            }
            .accessibilityLabel("Close voice")
            Spacer()
            Text("VOICE")
                .blackCaps(.subheadline, tracking: 1.5, color: .appTextMuted)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollView {
            let line = convo.transcript
            Text(line.isEmpty ? "Talk like a voice memo. I'm listening." : line)
                .font(.title3.weight(.medium))
                .foregroundStyle(line.isEmpty ? .appTextMuted : .appTextEmphasis)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.smooth(duration: 0.2), value: line)
        }
        .frame(maxHeight: 180)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Button { convo.finishNow() } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.appAccent)
            .disabled(!convo.hasContent)

            Text("Tap Done when you're finished.")
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 22)
    }

    // MARK: - Error

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(.appTextMuted)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.appTextEmphasis)
                .multilineTextAlignment(.center)
            Button("Type instead") { convo.cancel() }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.appAccent)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }
}
