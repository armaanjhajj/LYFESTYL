//
//  FoodAnalyzer.swift
//  LYFESTYL
//
//  Everything that touches Foundation Models. Two jobs, both on device:
//    1. look at a photo and itemize every food with nutrition and confidence
//    2. estimate nutrition for something the person typed
//
//  Photos are read for printed text first (Vision, also on device). The text
//  goes into the prompt so packaged products are named exactly, and numbers
//  printed on a label replace the model's estimate for that product.
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
    @ObservationIgnored private let log = Logger(subsystem: "Moments.LYFESTYL", category: "FoodAnalyzer")
    @ObservationIgnored private var warmSession: LanguageModelSession?

    private static let instructions = """
        You read photos of food for a calorie tracking app. List each distinct food or drink \
        that is the clear subject of the photo. Ignore things in the background or cut off at \
        the edges. Words printed on a package (flavor, claims, ingredients) describe that \
        product and are never separate items.
        Packaged products: identify the exact brand and product from the label and use the \
        nutrition printed on it for one container. Text read from the photo is given to you; \
        trust it over your own guess. The name is still the plain everyday name of the food.
        Everything else: estimate the visible amount and use typical USDA values for it, \
        including visible oils, sauces and dressings.
        Confidence is high when the food and the amount are clear, low when they are not.
        """

    init() { refresh() }

    func refresh() {
        switch model.availability {
        case .available:
            status = model.capabilities.contains(.vision) ? .ready : .textOnly
        case .unavailable(.deviceNotEligible):
            status = .unavailable("Photos need Apple Intelligence. Search still works.")
        case .unavailable(.appleIntelligenceNotEnabled):
            status = .unavailable("Turn on Apple Intelligence to log from photos.")
        case .unavailable(.modelNotReady):
            status = .unavailable("Apple Intelligence is still downloading.")
        case .unavailable:
            status = .unavailable("Photos can't be read right now. Search still works.")
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

    /// Itemize a photo. `onProgress` receives the foods as they are generated so
    /// the drawer can show each one arrive before the whole answer is done.
    /// `varied` samples instead of decoding greedily, so a retry can disagree.
    func analyze(
        _ image: CGImage,
        varied: Bool = false,
        onProgress: ([StreamedFood]) -> Void = { _ in }
    ) async throws -> [DraftItem] {
        let started = ContinuousClock.now
        defer { log.info("Photo read in \(ContinuousClock.now - started, privacy: .public)") }
        let label = await LabelReader.read(image)
        log.info("Label text: \(label.lines.count, privacy: .public) lines, facts found: \(!label.facts.isEmpty, privacy: .public)")
        let request = label.promptText.map {
            "Itemize the food and drink in this photo.\n\nText read from the photo:\n\($0)"
        } ?? "Itemize the food and drink in this photo."

        let session = takeSession()
        let stream = session.streamResponse(generating: FoodScan.self, options: options(varied: varied)) {
            request
            Attachment(image, orientation: .up)
        }
        var lastFoods: [StreamedFood] = []
        var final: GeneratedContent?
        for try await snapshot in stream {
            final = snapshot.rawContent
            let foods = (snapshot.content.items ?? []).enumerated().compactMap { StreamedFood($1, index: $0) }
            if foods != lastFoods {
                lastFoods = foods
                onProgress(foods)
            }
        }
        guard let final else { return [] }
        let scanned = try FoodScan(final).items.map {
            LabelFacts.Candidate(item: $0.draftItem, isPackaged: $0.isPackaged, product: $0.product)
        }
        let products = LabelFacts.nameKinds(
            LabelFacts.removeLabelWords(from: scanned, labelLines: label.lines),
            labelLines: label.lines
        )
        return LabelFacts.apply(label.facts, to: products, labelLines: label.lines)
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
        Logger(subsystem: "Moments.LYFESTYL", category: "FoodAnalyzer")
            .error("Generation failed: \(String(describing: error), privacy: .public)")
        if let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal:
                return "Try a closer shot of just the food."
            case .rateLimited, .timeout:
                return "Try again in a moment."
            case .unsupportedLanguageOrLocale:
                return "Your language isn't supported yet."
            default:
                break
            }
        }
        return "Try again, or search for it."
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
