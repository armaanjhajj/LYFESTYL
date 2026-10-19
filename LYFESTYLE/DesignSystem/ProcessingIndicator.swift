//
//  ProcessingIndicator.swift
//  LYFESTYL
//
//  A calm "thinking" indicator shown while a photo is analyzed on device.
//  Instead of a static "Analyzing…", it cycles through a bank of one-word
//  gerunds so the wait feels alive. Each instance starts on a different word.
//

import SwiftUI
import Combine

/// The word bank for the processing indicator, kitchen-flavored gerunds.
/// One source of truth.
enum ProcessingWords {
    static let all: [String] = [
        "Looking", "Squinting", "Spotting", "Sizing up", "Measuring", "Weighing",
        "Portioning", "Plating", "Tasting", "Sniffing", "Seasoning", "Simmering",
        "Stirring", "Whisking", "Slicing", "Dicing", "Peeling", "Toasting",
        "Grilling", "Searing", "Roasting", "Steaming", "Marinating", "Garnishing",
        "Counting", "Tallying", "Adding up", "Crunching", "Munching", "Nibbling",
        "Savoring", "Digesting", "Reading the menu", "Checking the label",
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
            // spinner signals activity; the word stays readable body text.
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
        .accessibilityLabel("Analyzing on device")
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
