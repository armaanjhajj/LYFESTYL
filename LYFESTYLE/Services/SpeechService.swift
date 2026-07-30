//
//  SpeechService.swift
//  LYFESTYL
//
//  On-device voice transcription (CLAUDE.md §4.5) using the iOS 26 Speech stack:
//  `SpeechAnalyzer` + `SpeechTranscriber`, fed live audio from an `AVAudioEngine`
//  tap. Everything stays on the phone, the transcript is then handed to the
//  same Foundation Models pipeline as a typed entry.
//
//  Verified against the Speech.framework swiftinterface (iOS 26.5 SDK):
//  SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:),
//  SpeechAnalyzer(modules:), analyzer.start(inputSequence:), transcriber.results
//  (AsyncSequence of Result{ text: AttributedString }), AssetInventory.
//

import Foundation
import Observation
import Speech
// @preconcurrency: AVFAudio's AVAudioPCMBuffer isn't Sendable, but we hand it
// straight to the analyzer on the audio thread without sharing it, silence the
// benign Sendable warning rather than copy buffers needlessly.
@preconcurrency import AVFoundation
@preconcurrency import AVFAudio

@MainActor
@Observable
final class SpeechService {

    enum RecordingState: Equatable {
        case idle
        case preparing       // downloading model / spinning up the engine
        case recording
        case finishing
    }

    private(set) var state: RecordingState = .idle
    /// Finalized transcript so far.
    private(set) var transcript: String = ""
    /// The latest volatile (in-progress) hypothesis, shown live while speaking.
    private(set) var volatileText: String = ""
    /// Recent input level 0...1 for a simple live meter (kept lightweight).
    private(set) var inputLevel: Double = 0
    private(set) var errorMessage: String?

    /// Everything captured so far, including the live hypothesis.
    var liveText: String {
        let v = volatileText.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return transcript }
        return transcript.isEmpty ? v : transcript + " " + v
    }

    var isRecording: Bool { state == .recording || state == .preparing }

    /// Whether transcription is usable on this device at all.
    static var isSupported: Bool { SpeechTranscriber.isAvailable }

    // Engine internals
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    // MARK: - Permissions

    /// Request microphone permission (the modern Speech API does on-device work
    /// and does not require legacy SFSpeechRecognizer authorization).
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard state == .idle else { return }
        errorMessage = nil
        transcript = ""
        volatileText = ""
        state = .preparing

        guard Self.isSupported else {
            fail("Voice transcription isn't available on this device.")
            return
        }
        guard await requestPermission() else {
            fail("Microphone access is needed to record a voice entry. You can enable it in Settings.")
            return
        }

        do {
            try await beginRecording()
            state = .recording
        } catch {
            fail("Couldn't start recording. \(error.localizedDescription)")
            await teardown()
        }
    }

    /// Stop recording and return the finalized transcript (trimmed).
    @discardableResult
    func stop() async -> String {
        guard state == .recording || state == .preparing else { return transcript }
        state = .finishing

        // Stop feeding audio.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()

        // Drain remaining results.
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Non-fatal: we still return whatever we have.
        }
        resultsTask?.cancel()
        _ = await resultsTask?.value

        // Fold any trailing volatile text into the final transcript.
        let trailing = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            transcript = transcript.isEmpty ? trailing : transcript + " " + trailing
        }
        volatileText = ""

        await teardown()
        state = .idle
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hard cancel with no result (e.g. user dismisses).
    func cancel() async {
        guard state != .idle else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        await teardown()
        transcript = ""
        volatileText = ""
        state = .idle
    }

    // MARK: - Internal

    private func beginRecording() async throws {
        // Resolve a supported locale, preferring the user's current one.
        let locale = await Self.resolveLocale()

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // Ensure the on-device model assets for this locale are installed.
        try await ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Pick the best analyzer-compatible audio format.
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechError.noCompatibleAudioFormat
        }
        self.analyzerFormat = analyzerFormat

        // Configure the audio session for recording.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Build the input stream the analyzer will consume.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation

        // Install a tap and forward converted buffers into the stream. The tap
        // runs on the realtime audio thread (nonisolated), so it captures the
        // continuation + converter as locals rather than reading actor state.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // The hardware format can be uninitialized (0 Hz) before the session is
        // fully active; bail rather than feed a bad format to the converter/tap.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechError.noCompatibleAudioFormat
        }
        let converter = AVAudioConverter(from: recordingFormat, to: analyzerFormat)
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            if let level = SpeechService.rms(of: buffer) {
                Task { @MainActor [weak self] in self?.inputLevel = level }
            }
            SpeechService.feed(
                buffer,
                into: continuation,
                converter: converter,
                recordingFormat: recordingFormat,
                analyzerFormat: analyzerFormat
            )
        }

        // Start consuming transcription results. The Task inherits this method's
        // MainActor isolation, so self access needs no await.
        resultsTask = Task { [weak self] in
            guard let self, let transcriber = self.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self.applyResult(text: text, isFinal: result.isFinal)
                }
            } catch {
                self.noteResultsError(error)
            }
        }

        // Begin analysis and the audio engine.
        try await analyzer.start(inputSequence: stream)
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Off-main audio-thread feed: convert the mic buffer to the analyzer's
    /// format and push it into the stream. Nonisolated + static so it never
    /// touches actor state; all inputs are passed in.
    nonisolated private static func feed(
        _ buffer: AVAudioPCMBuffer,
        into continuation: AsyncStream<AnalyzerInput>.Continuation,
        converter: AVAudioConverter?,
        recordingFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat
    ) {
        // If the formats already match, forward directly.
        if recordingFormat == analyzerFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        let ratio = analyzerFormat.sampleRate / recordingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, inStatus in
            if consumed {
                inStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inStatus.pointee = .haveData
            return buffer
        }

        if status == .haveData || status == .inputRanDry, outBuffer.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: outBuffer))
        }
    }

    private func applyResult(text: String, isFinal: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            guard !cleaned.isEmpty else { volatileText = ""; return }
            transcript = transcript.isEmpty ? cleaned : transcript + " " + cleaned
            volatileText = ""
        } else {
            volatileText = cleaned
        }
    }

    private func noteResultsError(_ error: Error) {
        // Cancellation is expected on stop; ignore it.
        if (error as? CancellationError) != nil { return }
        errorMessage = "Transcription stopped: \(error.localizedDescription)"
    }

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        if isInstalled { return }

        // Request and run a download for the required assets, if available.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private func teardown() async {
        if audioEngine.isRunning { audioEngine.stop() }
        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
        inputContinuation = nil
        resultsTask = nil
        inputLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .idle
    }

    /// Clear a surfaced error after the UI has shown it.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private static func resolveLocale() async -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return match
        }
        // Fall back to US English if the current locale isn't supported.
        let supported = await SpeechTranscriber.supportedLocales
        return supported.first(where: { $0.identifier(.bcp47).hasPrefix("en") }) ?? Locale(identifier: "en-US")
    }

    nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength { let s = samples[i]; sum += s * s }
        let rms = (sum / Float(frameLength)).squareRoot()
        // Map a rough dB range to 0...1.
        let normalized = max(0, min(1, Double(rms) * 8))
        return normalized
    }

    enum SpeechError: LocalizedError {
        case noCompatibleAudioFormat
        var errorDescription: String? {
            switch self {
            case .noCompatibleAudioFormat: "No compatible audio format for on-device transcription."
            }
        }
    }
}
