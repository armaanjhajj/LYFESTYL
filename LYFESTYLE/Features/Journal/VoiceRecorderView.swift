//
//  VoiceRecorderView.swift
//  LYFESTYL
//
//  Voice capture (CLAUDE.md §4.5): records with AVFoundation and transcribes
//  on-device with SpeechAnalyzer/SpeechTranscriber. The transcript is returned
//  to the Journal composer so it flows through the same pipeline as typed text.
//  Controls are native glass buttons; the mic visual is a simple level meter,
//  not a re-skinned system control.
//

import SwiftUI

struct VoiceRecorderView: View {
    var onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var speech = SpeechService()
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                if let error = speech.errorMessage {
                    errorState(error)
                } else {
                    micVisual
                    transcriptArea
                }

                Spacer(minLength: 12)

                if speech.errorMessage == nil {
                    controls
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Voice Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await cancel() } }
                        .tint(.appTextMuted)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard !didStart else { return }
            didStart = true
            await speech.start()
        }
        .onDisappear {
            // If dismissed by swipe while still active, clean up the engine.
            if speech.isRecording { Task { await speech.cancel() } }
        }
    }

    // MARK: - Pieces

    private var micVisual: some View {
        ZStack {
            Circle()
                .fill(Color.appAccent.opacity(0.16))
                .frame(width: 120, height: 120)
                .scaleEffect(reduceMotion ? 1 : (1 + speech.inputLevel * 0.5))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: speech.inputLevel)
            Circle()
                .fill(Color.appAccent.opacity(0.22))
                .frame(width: 86, height: 86)
            Image(systemName: speech.state == .recording ? "mic.fill" : "mic")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.appAccent)
        }
        .frame(height: 140)
        .accessibilityLabel(speech.state == .recording ? "Recording" : "Microphone")
    }

    private var transcriptArea: some View {
        ScrollView {
            Text(displayText)
                .font(.title3)
                .foregroundStyle(speech.liveText.isEmpty ? .appTextMuted : .appTextEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
        }
        .frame(maxHeight: 200)
    }

    private var displayText: String {
        switch speech.state {
        case .preparing: return speech.liveText.isEmpty ? "Preparing…" : speech.liveText
        case .recording: return speech.liveText.isEmpty ? "Listening… start talking." : speech.liveText
        case .finishing: return speech.liveText.isEmpty ? "Finishing…" : speech.liveText
        case .idle:      return speech.liveText
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 16) {
            Button {
                Task { await finish() }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glassProminent)
            .tint(.appAccent)
            .disabled(speech.state == .preparing)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(Solar.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.appText)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.appAccent)
        }
        .padding()
    }

    // MARK: - Actions

    private func finish() async {
        let transcript = await speech.stop()
        onComplete(transcript)
        dismiss()
    }

    private func cancel() async {
        await speech.cancel()
        dismiss()
    }
}
