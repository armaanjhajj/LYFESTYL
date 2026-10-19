//
//  LabelReader.swift
//  LYFESTYL
//
//  Reads the printed text in a photo with Vision, on device. Brand names and
//  label numbers are the difference between "protein shake, about 250 kcal"
//  and the exact product, so the text goes to the model as context and any
//  nutrition numbers go straight onto the food (see `LabelFacts`).
//

import CoreGraphics
import Vision

nonisolated enum LabelReader {

    struct Reading: Sendable {
        /// Recognized lines, in reading order.
        var lines: [String]
        var facts: LabelFacts

        static let empty = Reading(lines: [], facts: LabelFacts(lines: []))

        /// The text as prompt context, capped so a busy menu can't crowd out the photo.
        var promptText: String? {
            let text = lines.joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            return String(text.prefix(1200))
        }
    }

    static func read(_ image: CGImage) async -> Reading {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Ignore specks of text too small to matter at a glance.
        request.minimumTextHeightFraction = 0.008
        guard let observations = try? await request.perform(on: image) else { return .empty }
        let lines = observations
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence >= 0.3 }
            .map(\.string)
        return Reading(lines: lines, facts: LabelFacts(lines: lines))
    }
}
