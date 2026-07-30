//
//  VoiceConversation.swift
//  LYFESTYL
//
//  Drives voice mode: a single, continuous on-device transcription session. The
//  user talks like a voice memo, the orb reacts to their voice, the live
//  transcript builds, and when they tap Done the text flows back into the same
//  entry pipeline as a typed one. No assistant, no spoken replies, nothing leaves
//  the device. Degrades gracefully when transcription isn't available.
//

import Foundation
import Observation

@MainActor
@Observable
final class VoiceConversation {

    private(set) var phase: VoicePhase = .idle
    private(set) var errorMessage: String?

    let speech: SpeechService

    /// Called when the user finishes with text to save (the transcript).
    var onComplete: ((String) -> Void)?
    /// Called when the user finishes with nothing to save (cancel / empty / error).
    var onCancel: (() -> Void)?

    private var sessionTask: Task<Void, Never>?
    private var endContinuation: CheckedContinuation<Void, Never>?
    private var cancelled = false

    init() {
        self.speech = SpeechService()
    }

    /// The live transcript so far (finalized text plus the in-progress hypothesis).
    var transcript: String {
        speech.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasContent: Bool { !transcript.isEmpty }

    // MARK: - Control

    func start() {
        guard sessionTask == nil else { return }
        sessionTask = Task { await run() }
    }

    /// User tapped Done: stop and save the transcript.
    func finishNow() {
        phase = .finishing
        resumeEnd()
    }

    /// User dismissed: stop and save nothing.
    func cancel() {
        cancelled = true
        phase = .finishing
        resumeEnd()
    }

    private func resumeEnd() {
        endContinuation?.resume()
        endContinuation = nil
    }

    // MARK: - Session

    private func run() async {
        phase = .listening
        await speech.start()
        if !speech.isRecording {
            errorMessage = speech.errorMessage
                ?? "Voice isn't available on this device. You can type your entry instead."
        }

        // Stay listening until the user taps Done or Cancel.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            endContinuation = continuation
        }

        let text = speech.isRecording ? await speech.stop() : ""
        await speech.cancel()
        phase = .finishing

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cancelled || trimmed.isEmpty {
            onCancel?()
        } else {
            onComplete?(trimmed)
        }
    }
}
