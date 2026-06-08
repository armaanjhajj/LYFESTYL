//
//  Trends.swift
//  LYFESTYL
//
//  Pure aggregation for the Trends surface. Turns the flat list of insights into
//  daily time series (for Swift Charts) and per-category rank averages. Kept
//  free of UI so it's easy to reason about and test.
//

import Foundation

struct TrendPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let value: Double
}

enum TrendRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }
    var label: String { rawValue }
}

struct TrendCalculator {
    let insights: [Insight]
    var calendar: Calendar = .current

    private func startDate(for range: TrendRange) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
    }

    var domainEnd: Date { calendar.startOfDay(for: Date()) }

    func domainStart(_ range: TrendRange) -> Date { startDate(for: range) }

    /// Daily aggregated series for a metric within the range.
    func metricSeries(_ key: MetricKey, range: TrendRange) -> [TrendPoint] {
        let start = startDate(for: range)
        var byDay: [Date: [Double]] = [:]
        for insight in insights where insight.category == key.category {
            guard let value = insight.value(for: key) else { continue }
            let day = calendar.startOfDay(for: insight.entryDate)
            guard day >= start else { continue }
            byDay[day, default: []].append(value)
        }
        return byDay.map { day, values in
            let agg: Double
            switch key.aggregation {
            case .sum: agg = values.reduce(0, +)
            case .average: agg = values.reduce(0, +) / Double(values.count)
            }
            return TrendPoint(date: day, value: agg)
        }
        .sorted { $0.date < $1.date }
    }

    /// Daily average rank (1...5) for a category within the range.
    func rankSeries(_ category: InsightCategory, range: TrendRange) -> [TrendPoint] {
        let start = startDate(for: range)
        var byDay: [Date: [Int]] = [:]
        for insight in insights where insight.category == category {
            let day = calendar.startOfDay(for: insight.entryDate)
            guard day >= start else { continue }
            byDay[day, default: []].append(insight.rank.score)
        }
        return byDay.map { day, scores in
            TrendPoint(date: day, value: Double(scores.reduce(0, +)) / Double(scores.count))
        }
        .sorted { $0.date < $1.date }
    }

    /// Overall average rank score for a category within the range, if any.
    func averageScore(_ category: InsightCategory, range: TrendRange) -> Double? {
        let start = startDate(for: range)
        let scores = insights
            .filter { $0.category == category && calendar.startOfDay(for: $0.entryDate) >= start }
            .map { $0.rank.score }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    /// Which metrics have at least one data point in the range (for the picker).
    func availableMetrics(range: TrendRange) -> [MetricKey] {
        MetricKey.allCases.filter { !metricSeries($0, range: range).isEmpty }
    }

    /// Categories that have any rank data in the range.
    func availableCategories(range: TrendRange) -> [InsightCategory] {
        InsightCategory.allCases
            .filter { averageScore($0, range: range) != nil }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var hasAnyData: Bool { !insights.isEmpty }
}
