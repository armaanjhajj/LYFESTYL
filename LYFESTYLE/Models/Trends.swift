//
//  Trends.swift
//  LYFESTYL
//
//  Pure aggregation for the Trends surface. Neutral activity only: how often each
//  category gets logged over time, daily totals, and current streaks. No ranks, no
//  scores, no estimated numbers, the app reflects what you logged, it doesn't grade
//  it. Kept free of UI so it's easy to reason about and test.
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
    let entries: [JournalEntry]
    var calendar: Calendar = .current

    /// Only finished, categorized entries count toward activity.
    private var categorized: [(category: InsightCategory, day: Date)] {
        entries.compactMap { entry in
            guard let category = entry.category else { return nil }
            return (category, calendar.startOfDay(for: entry.entryDate))
        }
    }

    private func startDate(for range: TrendRange) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
    }

    var domainEnd: Date { calendar.startOfDay(for: Date()) }
    func domainStart(_ range: TrendRange) -> Date { startDate(for: range) }

    /// Daily count of entries for one category within the range.
    func countSeries(_ category: InsightCategory, range: TrendRange) -> [TrendPoint] {
        let start = startDate(for: range)
        var byDay: [Date: Int] = [:]
        for item in categorized where item.category == category && item.day >= start {
            byDay[item.day, default: 0] += 1
        }
        return byDay
            .map { TrendPoint(date: $0.key, value: Double($0.value)) }
            .sorted { $0.date < $1.date }
    }

    /// Total entries for one category within the range.
    func totalCount(_ category: InsightCategory, range: TrendRange) -> Int {
        let start = startDate(for: range)
        return categorized.filter { $0.category == category && $0.day >= start }.count
    }

    /// Total categorized entries within the range, across all categories.
    func totalEntries(range: TrendRange) -> Int {
        let start = startDate(for: range)
        return categorized.filter { $0.day >= start }.count
    }

    /// Daily entry totals across all categories within the range.
    func dailyTotalSeries(range: TrendRange) -> [TrendPoint] {
        let start = startDate(for: range)
        var byDay: [Date: Int] = [:]
        for item in categorized where item.day >= start {
            byDay[item.day, default: 0] += 1
        }
        return byDay
            .map { TrendPoint(date: $0.key, value: Double($0.value)) }
            .sorted { $0.date < $1.date }
    }

    /// The most recent run of consecutive days a category was logged. Counts back
    /// from the latest day it appears, so a finished streak still reads as a win.
    func currentStreak(_ category: InsightCategory) -> Int {
        let days = Set(categorized.filter { $0.category == category }.map { $0.day })
        guard let latest = days.max() else { return 0 }
        var streak = 0
        var cursor = latest
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Categories with at least one entry in the range, in display order.
    func availableCategories(range: TrendRange) -> [InsightCategory] {
        let start = startDate(for: range)
        let present = Set(categorized.filter { $0.day >= start }.map { $0.category })
        return InsightCategory.allCases
            .filter { present.contains($0) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var hasAnyData: Bool { !categorized.isEmpty }
}
