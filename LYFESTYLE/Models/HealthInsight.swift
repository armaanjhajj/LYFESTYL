//
//  HealthInsight.swift
//  LYFESTYL
//
//  One thing worth telling the user, with the evidence attached.
//
//  Every insight the app produces carries three things that most fitness apps leave out:
//
//    EVIDENCE. The actual numbers behind the claim, so it can be checked rather than
//    believed. A statement like "your resting heart rate is up" is worthless without
//    "68 bpm against a 60-day median of 63, and your day-to-day spread is 2".
//
//    CONFIDENCE. Whether this rests on a power meter and ninety days of data or on an
//    age-estimated max heart rate and eleven days. The UI renders these differently, and a
//    low-confidence insight says so in words rather than being quietly presented as fact.
//
//    NO JUDGEMENT. Insights describe and contextualise. They do not grade the person, assign
//    a score, or predict injury. The strongest thing the app will say is that a number is
//    outside its usual range and what the literature associates with that.
//

import SwiftUI

// MARK: - Confidence

/// How much weight an insight deserves.
nonisolated enum InsightConfidence: String, Comparable, Sendable, CaseIterable {
    /// Measured data, an adequate sample, and a statistical test that cleared its bar.
    case high
    /// Real data, but a modest sample or a partly estimated input.
    case moderate
    /// Enough to mention, not enough to act on. Always labelled as such.
    case exploratory

    var label: String {
        switch self {
        case .high:        "SOLID"
        case .moderate:    "REASONABLE"
        case .exploratory: "EARLY"
        }
    }

    /// The caveat shown with the insight, in plain words.
    var caveat: String? {
        switch self {
        case .high:        nil
        case .moderate:    "Based on a modest amount of data so far."
        case .exploratory: "Too early to lean on. Worth watching, not acting on."
        }
    }

    var symbolName: String {
        switch self {
        case .high:        "checkmark.seal.fill"
        case .moderate:    "circle.lefthalf.filled"
        case .exploratory: "circle.dotted"
        }
    }

    private var rank: Int {
        switch self {
        case .high: 2
        case .moderate: 1
        case .exploratory: 0
        }
    }

    static func < (a: InsightConfidence, b: InsightConfidence) -> Bool { a.rank < b.rank }
}

// MARK: - Kind

/// What area an insight is about, which drives its icon and grouping.
nonisolated enum InsightKind: String, Sendable, CaseIterable, Identifiable {
    case trainingLoad
    case recovery
    case sleep
    case endurance
    case strength
    case relationship
    case consistency
    case milestone
    case dataQuality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trainingLoad: "TRAINING LOAD"
        case .recovery:     "RECOVERY"
        case .sleep:        "SLEEP"
        case .endurance:    "ENDURANCE"
        case .strength:     "STRENGTH"
        case .relationship: "PATTERNS"
        case .consistency:  "CONSISTENCY"
        case .milestone:    "MILESTONES"
        case .dataQuality:  "YOUR DATA"
        }
    }

    var symbolName: String {
        switch self {
        case .trainingLoad: "chart.line.uptrend.xyaxis"
        case .recovery:     "heart.text.square.fill"
        case .sleep:        "bed.double.fill"
        case .endurance:    "figure.run"
        case .strength:     "dumbbell.fill"
        case .relationship: "arrow.triangle.branch"
        case .consistency:  "calendar"
        case .milestone:    "trophy.fill"
        case .dataQuality:  "sparkle.magnifyingglass"
        }
    }

    var accent: Color {
        switch self {
        case .trainingLoad: Solar.blue
        case .recovery:     Solar.magenta
        case .sleep:        Solar.violet
        case .endurance:    Solar.cyan
        case .strength:     Solar.green
        case .relationship: Solar.orange
        case .consistency:  Solar.yellow
        case .milestone:    Solar.green
        case .dataQuality:  Solar.base1
        }
    }

    /// Display order in the insights list.
    var sortIndex: Int {
        switch self {
        case .recovery:     0
        case .trainingLoad: 1
        case .sleep:        2
        case .endurance:    3
        case .strength:     4
        case .relationship: 5
        case .milestone:    6
        case .consistency:  7
        case .dataQuality:  8
        }
    }
}

// MARK: - Tone

/// How an insight should read. Never a grade, only a direction of attention.
nonisolated enum InsightTone: String, Sendable {
    /// Something is worth a closer look.
    case attention
    /// Something is going well.
    case positive
    /// A plain observation with no valence.
    case neutral

    var accent: Color {
        switch self {
        case .attention: Solar.orange
        case .positive:  Solar.green
        case .neutral:   Solar.base1
        }
    }
}

// MARK: - Evidence

/// One number behind an insight.
nonisolated struct InsightEvidence: Identifiable, Hashable, Sendable {
    var label: String
    var value: String
    /// Optional context, such as the baseline the value is measured against.
    var context: String?

    var id: String { label }

    init(_ label: String, _ value: String, context: String? = nil) {
        self.label = label
        self.value = value
        self.context = context
    }
}

// MARK: - Sparkline payload

/// A small series an insight can draw to show its own shape.
nonisolated struct InsightSeries: Hashable, Sendable {
    var points: [Point]
    /// A reference level to draw as a baseline, when there is one.
    var baseline: Double?
    var unit: String?

    nonisolated struct Point: Hashable, Sendable, Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var isEmpty: Bool { points.count < 2 }

    var range: ClosedRange<Double>? {
        let values = points.map(\.value) + [baseline].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return nil }
        return low == high ? (low - 1)...(high + 1) : low...high
    }
}

// MARK: - The insight

nonisolated struct HealthInsight: Identifiable, Hashable, Sendable {

    /// Stable across recomputation, so the UI can animate and the user can dismiss one
    /// without it reappearing the next time the analysis runs.
    var id: String
    var kind: InsightKind
    var tone: InsightTone
    var confidence: InsightConfidence

    /// Short and declarative, rendered in the app's ALL CAPS header treatment.
    var headline: String
    /// One or two sentences. Describes, contextualises, never grades.
    var detail: String
    /// The numbers behind it.
    var evidence: [InsightEvidence]
    /// Where the underlying data came from.
    var sources: [DataSource]
    /// A series to draw, when the insight has a shape worth showing.
    var series: InsightSeries?
    /// Ranking weight. Higher shows first within a kind.
    var priority: Double
    /// A specific workout this is about, for navigation.
    var workoutID: String?
    /// The metric this is about, for navigation.
    var metric: WellnessMetric?

    init(
        id: String,
        kind: InsightKind,
        tone: InsightTone = .neutral,
        confidence: InsightConfidence,
        headline: String,
        detail: String,
        evidence: [InsightEvidence] = [],
        sources: [DataSource] = [],
        series: InsightSeries? = nil,
        priority: Double = 0,
        workoutID: String? = nil,
        metric: WellnessMetric? = nil
    ) {
        self.id = id
        self.kind = kind
        self.tone = tone
        self.confidence = confidence
        self.headline = headline
        self.detail = detail
        self.evidence = evidence
        self.sources = sources
        self.series = series
        self.priority = priority
        self.workoutID = workoutID
        self.metric = metric
    }

    var symbolName: String { kind.symbolName }

    /// Accent: the tone leads where there is one, otherwise the kind's colour.
    var accent: Color { tone == .neutral ? kind.accent : tone.accent }

    /// Sort key: attention first, then confidence, then priority.
    var sortWeight: Double {
        var weight = priority
        if tone == .attention { weight += 1000 }
        switch confidence {
        case .high:        weight += 300
        case .moderate:    weight += 150
        case .exploratory: weight += 0
        }
        return weight
    }
}

// MARK: - Collection helpers

nonisolated extension Array where Element == HealthInsight {

    /// Ranked for display: most important first.
    var ranked: [HealthInsight] {
        sorted { a, b in
            if a.sortWeight != b.sortWeight { return a.sortWeight > b.sortWeight }
            return a.kind.sortIndex < b.kind.sortIndex
        }
    }

    /// Grouped by kind, in display order, each group internally ranked.
    var groupedByKind: [(kind: InsightKind, insights: [HealthInsight])] {
        Dictionary(grouping: self, by: \.kind)
            .map { (kind: $0.key, insights: $0.value.ranked) }
            .sorted { $0.kind.sortIndex < $1.kind.sortIndex }
    }

    /// Only the ones asking for attention.
    var needingAttention: [HealthInsight] {
        filter { $0.tone == .attention }.ranked
    }

    func excluding(ids: Set<String>) -> [HealthInsight] {
        filter { !ids.contains($0.id) }
    }
}
