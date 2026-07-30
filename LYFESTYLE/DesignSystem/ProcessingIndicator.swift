//
//  ProcessingIndicator.swift
//  LYFESTYL
//
//  A calm, Claude-Code-style "thinking" indicator shown while an entry is being
//  broken down on device. Instead of a static "Analyzing…", it cycles through a
//  bank of one-word gerunds (Pondering, Untangling, Synthesizing…) so a pending
//  entry feels alive while the model works. Each instance starts on a different
//  word so a list of processing rows doesn't tick in lockstep.
//

import SwiftUI
import Combine

/// The word bank for the processing indicator, reflective, journal-flavored
/// gerunds grouped loosely by vibe. One source of truth.
enum ProcessingWords {
    static let all: [String] = [
        // Reading / absorbing
        "Perusing", "Skimming", "Absorbing", "Imbibing", "Digesting", "Savoring",
        "Steeping", "Marinating", "Soaking", "Osmosing", "Inhaling", "Devouring",
        "Poring", "Squinting", "Rereading",
        // Reflecting / thinking
        "Pondering", "Mulling", "Musing", "Ruminating", "Contemplating", "Meditating",
        "Brooding", "Chewing", "Stewing", "Percolating", "Incubating", "Gestating",
        "Daydreaming", "Wondering", "Philosophizing",
        // Detective energy
        "Sleuthing", "Snooping", "Decoding", "Deciphering", "Untangling", "Unraveling",
        "Excavating", "Unearthing", "Dusting", "Probing", "Sifting", "Combing",
        "Scouring", "Triangulating", "Cross-referencing",
        // Pattern hunting
        "Connecting", "Threading", "Weaving", "Mapping", "Charting", "Plotting",
        "Tracing", "Linking", "Correlating", "Clustering", "Spotting", "Noticing",
        "Surfacing", "Distilling", "Synthesizing",
        // Emotional read
        "Empathizing", "Attuning", "Feeling", "Sensing", "Vibing", "Resonating",
        "Hearing", "Listening", "Holding", "Witnessing", "Honoring", "Validating",
        "Acknowledging", "Appreciating", "Understanding",
        // Gentle / whimsical
        "Nodding", "Humming", "Murmuring", "Sipping", "Wandering", "Meandering",
        "Lingering", "Dwelling", "Nestling", "Cozying", "Tiptoeing", "Drifting",
        "Floating", "Basking", "Gazing",
        // Processing / working
        "Journaling", "Annotating", "Underlining", "Highlighting", "Bookmarking",
        "Margining", "Indexing", "Cataloging", "Archiving", "Compiling", "Tallying",
        "Weighing", "Measuring", "Calibrating", "Crystallizing",
    ]

    /// A starting index, varied per call so adjacent rows don't sync up.
    static func seed() -> Int { Int.random(in: 0..<all.count) }
}

struct ProcessingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = ProcessingWords.seed()

    /// Cycle a little slower than a spinner so the words are readable, not frantic.
    private let timer = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.appAccent)
            // Accent (green) can't carry small text on the beige base, the green
            // spinner signals activity; the word stays readable body text (§3.1).
            Text(ProcessingWords.all[index] + "…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.appText)
                .contentTransition(.opacity)
                .monospacedDigit()
        }
        .onReceive(timer) { _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                index = nextIndex()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analyzing entry on device")
    }

    private func nextIndex() -> Int {
        guard ProcessingWords.all.count > 1 else { return index }
        var next = index
        while next == index { next = ProcessingWords.seed() }
        return next
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        ProcessingIndicator()
    }
}
