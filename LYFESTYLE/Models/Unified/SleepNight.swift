//
//  SleepNight.swift
//  LYFESTYL
//
//  One night's sleep, normalized. Garmin writes staged sleep into Apple Health, as
//  does Apple Watch, so both arrive as HealthKit sleep-analysis samples and both
//  land here.
//
//  The hard part of sleep data is that samples OVERLAP: a coarse "asleep" block
//  often covers the same minutes as a staged Core/Deep/REM breakdown of that block,
//  and two devices can both describe one night. Naively summing double-counts and
//  produces eight hours of "deep sleep." So every duration here comes from
//  interval UNION arithmetic (see `SleepAssembler`), never from a raw sum.
//
//  Stages are reported only when the source actually staged the night. A watch that
//  recorded a single undifferentiated block leaves the stage fields nil rather than
//  guessing a split.
//

import SwiftUI

/// A staged or unstaged night of sleep. All durations are seconds.
nonisolated struct SleepNight: Identifiable, Hashable, Codable, Sendable {

    /// The calendar day the night is credited to: the morning the user woke up.
    /// This is the convention Apple Health uses, and it is what makes "last night"
    /// unambiguous.
    var date: Date

    var bedtime: Date
    var wakeTime: Date

    /// Union of every in-bed and asleep interval.
    var inBedSeconds: Double
    /// Union of the intervals in any asleep state. The headline number.
    var asleepSeconds: Double
    /// Time awake between falling asleep and finally rising.
    var awakeSeconds: Double

    // Stage durations, nil when the source did not stage the night.
    var deepSeconds: Double?
    var coreSeconds: Double?
    var remSeconds: Double?
    /// Asleep time the source did not attribute to a stage.
    var unspecifiedSeconds: Double?

    /// Distinct awakenings after sleep onset.
    var awakenings: Int?

    var source: DataSource

    init(
        date: Date,
        bedtime: Date,
        wakeTime: Date,
        inBedSeconds: Double,
        asleepSeconds: Double,
        awakeSeconds: Double = 0,
        deepSeconds: Double? = nil,
        coreSeconds: Double? = nil,
        remSeconds: Double? = nil,
        unspecifiedSeconds: Double? = nil,
        awakenings: Int? = nil,
        source: DataSource
    ) {
        self.date = date
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.inBedSeconds = inBedSeconds
        self.asleepSeconds = asleepSeconds
        self.awakeSeconds = awakeSeconds
        self.deepSeconds = deepSeconds
        self.coreSeconds = coreSeconds
        self.remSeconds = remSeconds
        self.unspecifiedSeconds = unspecifiedSeconds
        self.awakenings = awakenings
        self.source = source
    }

    var id: Date { date }

    var asleepHours: Double { asleepSeconds / 3600 }
    var inBedHours: Double { inBedSeconds / 3600 }

    /// Whether the source broke the night into stages.
    var isStaged: Bool {
        (deepSeconds ?? 0) > 0 || (remSeconds ?? 0) > 0 || (coreSeconds ?? 0) > 0
    }

    /// Sleep efficiency: asleep time as a fraction of time in bed. Nil when the
    /// source reported no separate in-bed period (many wrist-only sources do not),
    /// because computing it against asleep time would always return 1.0 and read as
    /// a perfect score that means nothing.
    var efficiency: Double? {
        guard inBedSeconds > asleepSeconds, inBedSeconds > 0 else { return nil }
        return asleepSeconds / inBedSeconds
    }

    /// Fraction of asleep time in a stage, nil when unstaged.
    func stageFraction(_ stage: SleepStage) -> Double? {
        guard asleepSeconds > 0, isStaged else { return nil }
        guard let seconds = self[stage] else { return nil }
        return seconds / asleepSeconds
    }

    subscript(stage: SleepStage) -> Double? {
        switch stage {
        case .deep:        deepSeconds
        case .core:        coreSeconds
        case .rem:         remSeconds
        case .unspecified: unspecifiedSeconds
        case .awake:       awakeSeconds
        }
    }

    /// The clock midpoint of the sleep period, used for the Sleep Regularity Index
    /// and for spotting a drifting schedule.
    var midSleep: Date {
        bedtime.addingTimeInterval(wakeTime.timeIntervalSince(bedtime) / 2)
    }

    /// Mid-sleep as hours after local midnight, wrapped into a continuous scale
    /// centred on the small hours so a 23:40 midpoint and a 00:20 midpoint read as
    /// forty minutes apart rather than twenty-three hours.
    func midSleepHour(calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: midSleep)
        let raw = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
        // Shift the discontinuity to midday: a midpoint of 14:00 is unusual enough
        // that placing the seam there is safe for essentially every sleeper.
        return raw < 12 ? raw : raw - 24
    }

    /// Bedtime as hours after local midnight, on the same continuous scale.
    func bedtimeHour(calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: bedtime)
        let raw = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
        return raw < 12 ? raw : raw - 24
    }
}

/// The sleep stages HealthKit distinguishes. `core` is Apple's name for light
/// sleep, kept as-is so the vocabulary matches what the user sees in Health.
nonisolated enum SleepStage: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case deep
    case rem
    case core
    case unspecified
    case awake

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deep:        "Deep"
        case .rem:         "REM"
        case .core:        "Core"
        case .unspecified: "Asleep"
        case .awake:       "Awake"
        }
    }

    var accent: Color {
        switch self {
        case .deep:        Solar.violet
        case .rem:         Solar.cyan
        case .core:        Solar.blue
        case .unspecified: Solar.base1
        case .awake:       Solar.orange
        }
    }

    /// Stages that constitute being asleep.
    static let asleepStages: [SleepStage] = [.deep, .rem, .core, .unspecified]

    /// Typical adult proportion of total sleep time, as a reference range only.
    /// These are population reference bands from the sleep literature, offered as
    /// context and never as a score. Nil for stages without a meaningful band.
    var typicalFractionRange: ClosedRange<Double>? {
        switch self {
        case .deep: 0.13...0.23   // slow-wave sleep, roughly 13 to 23 percent
        case .rem:  0.20...0.25   // REM, roughly 20 to 25 percent
        case .core: 0.45...0.55   // light/N1+N2, roughly half the night
        case .unspecified, .awake: nil
        }
    }
}

// MARK: - Interval union arithmetic

/// Builds a `SleepNight` from raw, possibly overlapping, possibly multi-source
/// sleep intervals. Every duration is produced by unioning intervals, which is the
/// only way to get an honest total when a coarse "asleep" block and its staged
/// breakdown describe the same minutes.
nonisolated enum SleepAssembler {

    /// One raw interval as a source reported it.
    struct Interval: Hashable, Sendable {
        var start: Date
        var end: Date
        var stage: SleepStage
        var source: DataSource

        var seconds: Double { max(0, end.timeIntervalSince(start)) }
    }

    /// Merge overlapping intervals and return the total covered seconds.
    static func unionSeconds(_ intervals: [Interval]) -> Double {
        unionRanges(intervals).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// Merge overlapping intervals into disjoint spans, in chronological order.
    static func unionRanges(_ intervals: [Interval]) -> [(start: Date, end: Date)] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var merged: [(start: Date, end: Date)] = []
        var currentStart = sorted[0].start
        var currentEnd = sorted[0].end
        for interval in sorted.dropFirst() {
            if interval.start <= currentEnd {
                currentEnd = max(currentEnd, interval.end)
            } else {
                merged.append((currentStart, currentEnd))
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        merged.append((currentStart, currentEnd))
        return merged
    }

    /// Assemble one night. Returns nil when the intervals contain no actual sleep.
    ///
    /// Stage durations are unioned WITHIN a stage, then a staged night's total is
    /// preferred over any coarse block, because summing "asleep" alongside
    /// "deep + core + REM" would count the night twice. The `unspecified` bucket is
    /// only the part of the asleep union that no stage covered.
    static func assemble(
        intervals: [Interval],
        calendar: Calendar = .current
    ) -> SleepNight? {
        let asleep = intervals.filter { SleepStage.asleepStages.contains($0.stage) }
        guard !asleep.isEmpty else { return nil }

        let asleepSeconds = unionSeconds(asleep)
        guard asleepSeconds > 0 else { return nil }

        let inBedIntervals = intervals   // in-bed is the union of everything reported
        let inBedSeconds = max(unionSeconds(inBedIntervals), asleepSeconds)

        let awakeIntervals = intervals.filter { $0.stage == .awake }
        let awakeSeconds = unionSeconds(awakeIntervals)

        // Per-stage unions. Only count a stage if the source actually reported it.
        func staged(_ stage: SleepStage) -> Double? {
            let matching = intervals.filter { $0.stage == stage }
            guard !matching.isEmpty else { return nil }
            return unionSeconds(matching)
        }
        let deep = staged(.deep)
        let core = staged(.core)
        let rem = staged(.rem)

        // Whatever asleep time the explicit stages did not cover.
        var unspecified: Double?
        let explicitStageTotal = (deep ?? 0) + (core ?? 0) + (rem ?? 0)
        if explicitStageTotal > 0 {
            let remainder = asleepSeconds - explicitStageTotal
            // Only report a remainder when it is a real gap, not float noise.
            unspecified = remainder > 60 ? remainder : nil
        } else {
            unspecified = asleepSeconds
        }

        let spans = unionRanges(asleep)
        guard let firstSpan = spans.first, let lastSpan = spans.last else { return nil }

        // In-bed brackets the night when the source reported it.
        let bedSpans = unionRanges(inBedIntervals)
        let bedtime = min(bedSpans.first?.start ?? firstSpan.start, firstSpan.start)
        let wakeTime = max(bedSpans.last?.end ?? lastSpan.end, lastSpan.end)

        // Awakenings: gaps between disjoint asleep spans.
        let awakenings = max(0, spans.count - 1)

        // Credit the night to the wake day, matching Apple Health. A nap that ends
        // the same day it started is credited to that day too.
        let day = calendar.startOfDay(for: wakeTime)

        // The source that contributed the most asleep time owns the record.
        var perSource: [DataSource: Double] = [:]
        for interval in asleep {
            perSource[interval.source, default: 0] += interval.seconds
        }
        let source = perSource.max { a, b in
            if a.value == b.value { return a.key.fieldPriority < b.key.fieldPriority }
            return a.value < b.value
        }?.key ?? .appleHealth

        return SleepNight(
            date: day,
            bedtime: bedtime,
            wakeTime: wakeTime,
            inBedSeconds: inBedSeconds,
            asleepSeconds: asleepSeconds,
            awakeSeconds: awakeSeconds,
            deepSeconds: deep,
            coreSeconds: core,
            remSeconds: rem,
            unspecifiedSeconds: unspecified,
            awakenings: awakenings > 0 ? awakenings : nil,
            source: source
        )
    }

    /// Split a flat run of intervals into nights, then assemble each. Intervals
    /// separated by more than `gapHours` of no data are treated as different sleep
    /// periods, which correctly separates a night from the next afternoon's nap.
    static func assembleNights(
        intervals: [Interval],
        gapHours: Double = 4,
        calendar: Calendar = .current
    ) -> [SleepNight] {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var groups: [[Interval]] = []
        var current: [Interval] = [sorted[0]]
        var currentEnd = sorted[0].end

        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(currentEnd) > gapHours * 3600 {
                groups.append(current)
                current = [interval]
                currentEnd = interval.end
            } else {
                current.append(interval)
                currentEnd = max(currentEnd, interval.end)
            }
        }
        groups.append(current)

        // One night per wake-day: if two groups land on the same day (a night plus
        // a nap), keep the longer as the night. Naps are not sleep debt data.
        var byDay: [Date: SleepNight] = [:]
        for group in groups {
            guard let night = assemble(intervals: group, calendar: calendar) else { continue }
            if let existing = byDay[night.date], existing.asleepSeconds >= night.asleepSeconds {
                continue
            }
            byDay[night.date] = night
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}
