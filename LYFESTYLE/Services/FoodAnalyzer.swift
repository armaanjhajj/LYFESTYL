//
//  FoodAnalyzer.swift
//  LYFESTYL
//
//  Everything that touches Foundation Models. Two jobs, both on device:
//    1. look at a photo and itemize every food with nutrition and confidence
//    2. estimate nutrition for something the person typed
//
//  Each request gets a fresh session (nothing carries between meals), and the
//  next session is created and prewarmed ahead of time so a snap starts
//  generating immediately.
//

import CoreGraphics
import FoundationModels
import ImageIO
import Observation
import os

@Observable
final class FoodAnalyzer {

    enum Status: Equatable {
        /// Ready for photos and text.
        case ready
        /// The model runs but this device's model can't take images.
        case textOnly
        case unavailable(String)

        var canReadPhotos: Bool { self == .ready }
        var canEstimateText: Bool { self == .ready || self == .textOnly }
    }

    private(set) var status: Status = .unavailable("Checking on-device AI…")

    @ObservationIgnored private let model = SystemLanguageModel.default
    @ObservationIgnored private let log = Logger(subsystem: "Moments.LYFESTYLE", category: "FoodAnalyzer")
    @ObservationIgnored private var warmSession: LanguageModelSession?

    private static let instructions = """
        You estimate nutrition for a calorie tracking app. Identify each food and drink, \
        estimate the amount, then give calories and grams of protein, carbohydrate and fat \
        for that amount using typical values for the food as it is usually prepared, \
        including visible oils, sauces and dressings. Prefer common names. \
        Be honest about confidence.
        """

    init() { refresh() }

    func refresh() {
        switch model.availability {
        case .available:
            status = model.capabilities.contains(.vision) ? .ready : .textOnly
        case .unavailable(.deviceNotEligible):
            status = .unavailable("This iPhone doesn't support Apple Intelligence, so photos can't be read. You can still search and log foods.")
        case .unavailable(.appleIntelligenceNotEnabled):
            status = .unavailable("Turn on Apple Intelligence in Settings to log meals from photos. You can still search and log foods.")
        case .unavailable(.modelNotReady):
            status = .unavailable("Apple Intelligence is still downloading. Photo logging will work once it finishes.")
        case .unavailable:
            status = .unavailable("On-device AI isn't available right now. You can still search and log foods.")
        }
        log.info("Model status: \(String(describing: self.status), privacy: .public)")
    }

    /// Get a session loaded before the shutter is pressed.
    func prewarm() {
        guard status.canEstimateText, warmSession == nil else { return }
        let session = makeSession()
        session.prewarm()
        warmSession = session
    }

    /// Itemize a photo. `onProgress` receives food names as they are generated so
    /// the drawer can show what's been found before the numbers finish.
    /// `varied` samples instead of decoding greedily, so a retry can disagree.
    func analyze(
        _ image: CGImage,
        varied: Bool = false,
        onProgress: ([String]) -> Void = { _ in }
    ) async throws -> [DraftItem] {
        let started = ContinuousClock.now
        defer { log.info("Photo read in \(ContinuousClock.now - started, privacy: .public)") }
        let session = takeSession()
        let stream = session.streamResponse(generating: FoodScan.self, options: options(varied: varied)) {
            "Itemize the food and drink in this photo."
            Attachment(image, orientation: .up)
        }
        var lastNames: [String] = []
        var final: GeneratedContent?
        for try await snapshot in stream {
            final = snapshot.rawContent
            let names = (snapshot.content.items ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
            if names != lastNames {
                lastNames = names
                onProgress(names)
            }
        }
        guard let final else { return [] }
        return try FoodScan(final).items.map(\.draftItem).filter { !$0.food.name.isEmpty }
    }

    /// Estimate what the person described, split into items if they listed several.
    func estimate(_ description: String, varied: Bool = false) async throws -> [DraftItem] {
        let session = takeSession()
        let response = try await session.respond(generating: FoodScan.self, options: options(varied: varied)) {
            "Estimate nutrition for what I ate: \(description)"
            "If no amount is given, assume one typical serving."
        }
        return response.content.items.map(\.draftItem).filter { !$0.food.name.isEmpty }
    }

    /// A readable message for any generation failure.
    static func message(for error: any Error) -> String {
        Logger(subsystem: "Moments.LYFESTYLE", category: "FoodAnalyzer")
            .error("Generation failed: \(String(describing: error), privacy: .public)")
        if let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal:
                return "This photo couldn't be read. Try a closer shot of just the food."
            case .rateLimited:
                return "On-device AI is busy. Try again in a moment."
            case .timeout:
                return "That took too long. Try again."
            case .unsupportedLanguageOrLocale:
                return "On-device AI doesn't support your language yet."
            default:
                break
            }
        }
        return "Something went wrong reading this. Try again, or search for the food."
    }

    // MARK: - Sessions

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Self.instructions)
    }

    private func takeSession() -> LanguageModelSession {
        let session = warmSession ?? makeSession()
        warmSession = nil
        return session
    }

    private func options(varied: Bool) -> GenerationOptions {
        varied ? GenerationOptions(temperature: 0.8) : GenerationOptions(samplingMode: .greedy)
    }
}
