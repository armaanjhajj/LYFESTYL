//
//  TrendsView.swift
//  LYFESTYL
//
//  Activity over time with Swift Charts, never hand-drawn. Neutral by design: how
//  often each category gets logged, current streaks, and total logging over time.
//  No ranks, no scores, no estimated numbers, the app reflects what you logged, it
//  doesn't grade it. Calm and Health-like.
//

import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(JournalStore.self) private var store
    @State private var range: TrendRange = .month

    private var calc: TrendCalculator { TrendCalculator(entries: store.entries) }

    var body: some View {
        ScrollView {
            if !calc.hasAnyData {
                EmptyStateView(
                    symbol: "chart.xyaxis.line",
                    title: "No activity yet",
                    message: "Log a few entries and your category activity will build here."
                )
                .padding(.top, 80)
            } else {
                VStack(spacing: 20) {
                    rangePicker
                    byCategoryCard
                    streaksCard
                    overTimeCard
                }
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Range

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - By category

    private var byCategoryCard: some View {
        let categories = calc.availableCategories(range: range)
        let counts = categories.map { (category: $0, count: calc.totalCount($0, range: range)) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BY CATEGORY")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                Text("\(calc.totalEntries(range: range)) total")
                    .font(.caption)
                    .foregroundStyle(Color.appTextMuted)
            }

            if counts.isEmpty {
                Text("No entries in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            } else {
                Chart(counts, id: \.category) { item in
                    BarMark(
                        x: .value("Entries", item.count),
                        y: .value("Category", item.category.label)
                    )
                    .foregroundStyle(item.category.accent.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text("\(item.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appTextMuted)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(counts.count) * 38 + 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Streaks

    private var streaksCard: some View {
        let rows = calc.availableCategories(range: range)
            .map { (category: $0, streak: calc.currentStreak($0)) }
            .filter { $0.streak > 0 }
            .sorted { $0.streak > $1.streak }
        return VStack(alignment: .leading, spacing: 14) {
            Text("CURRENT STREAKS")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            if rows.isEmpty {
                Text("Log on consecutive days to build a streak.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            } else {
                ForEach(rows, id: \.category) { row in
                    HStack(spacing: 12) {
                        CategoryIcon(category: row.category, size: 32)
                        Text(row.category.label)
                            .categoryLabel(color: .appTextEmphasis)
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(row.category.accent)
                            Text("\(row.streak) \(row.streak == 1 ? "day" : "days")")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.appTextEmphasis)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.category.label) streak \(row.streak) days")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Over time

    private var overTimeCard: some View {
        let series = calc.dailyTotalSeries(range: range)
        return VStack(alignment: .leading, spacing: 14) {
            Text("LOGGING OVER TIME")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            if series.isEmpty {
                Text("No entries in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            } else {
                Chart(series) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Entries", point.value)
                    )
                    .foregroundStyle(Color.appAccent.gradient)
                    .cornerRadius(3)
                }
                .chartXScale(domain: calc.domainStart(range)...calc.domainEnd)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
