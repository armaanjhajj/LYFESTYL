//
//  TrendsView.swift
//  LYFESTYL
//
//  Trends over time (CLAUDE.md §1) with Swift Charts — never hand-drawn. Shows
//  average rank per category (native Gauge), a metric time series, and rank over
//  time. Calm and Health-like.
//

import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(JournalStore.self) private var store
    @State private var range: TrendRange = .month
    @State private var selectedMetric: MetricKey?
    @State private var selectedCategory: InsightCategory?

    private var calc: TrendCalculator { TrendCalculator(insights: store.allInsights) }

    var body: some View {
        ScrollView {
            if !calc.hasAnyData {
                EmptyStateView(
                    symbol: "chart.xyaxis.line",
                    title: "No trends yet",
                    message: "Log a few entries and your nutrition, activity, sleep, and health trends will build here."
                )
                .padding(.top, 80)
            } else {
                VStack(spacing: 20) {
                    rangePicker
                    averageRankCard
                    metricChartCard
                    rankTrendCard
                }
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: ensureSelections)
        .onChange(of: range) { _, _ in ensureSelections() }
    }

    // MARK: - Range

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Average rank

    private var averageRankCard: some View {
        let categories = calc.availableCategories(range: range)
        return VStack(alignment: .leading, spacing: 14) {
            Text("AVERAGE RANK")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            if categories.isEmpty {
                Text("No ranked entries in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            } else {
                ForEach(categories) { category in
                    if let score = calc.averageScore(category, range: range) {
                        rankRow(category: category, score: score)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func rankRow(category: InsightCategory, score: Double) -> some View {
        let rank = Rank(roundedScore: score)
        return HStack(spacing: 12) {
            CategoryIcon(category: category, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.label).categoryLabel(color: .appTextEmphasis)
                    Spacer()
                    Text(rank.label)
                        .font(.caption2.weight(.black))
                        .tracking(0.5)
                        .foregroundStyle(rank.color)
                }
                Gauge(value: score, in: 1...5) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(rank.color)
                    .labelsHidden()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.label) average rank \(rank.label)")
    }

    // MARK: - Metric chart

    private var metricChartCard: some View {
        let metrics = calc.availableMetrics(range: range)
        let key = selectedMetric ?? metrics.first
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("METRICS")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                if !metrics.isEmpty, let key {
                    Menu {
                        ForEach(metrics) { metric in
                            Button(metric.label) { selectedMetric = metric }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(key.label)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                    }
                }
            }

            if let key {
                let series = calc.metricSeries(key, range: range)
                metricSummary(key: key, series: series)
                metricChart(key: key, series: series)
            } else {
                Text("No metric estimates in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func metricSummary(key: MetricKey, series: [TrendPoint]) -> some View {
        let avg = series.isEmpty ? 0 : series.map(\.value).reduce(0, +) / Double(series.count)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key.format(avg, includeUnit: false))
                .font(.largeTitle)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.appTextEmphasis)
            Text(key.unit + " · avg/logged day")
                .font(.caption)
                .foregroundStyle(Color.appTextMuted)
        }
    }

    @ViewBuilder
    private func metricChart(key: MetricKey, series: [TrendPoint]) -> some View {
        Chart(series) { point in
            if key.aggregation == .average {
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(key.label, point.value)
                )
                .foregroundStyle(key.category.accent)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(key.label, point.value)
                )
                .foregroundStyle(key.category.accent)
            } else {
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(key.label, point.value)
                )
                .foregroundStyle(key.category.accent.gradient)
                .cornerRadius(4)
            }
        }
        .chartXScale(domain: calc.domainStart(range)...calc.domainEnd)
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
    }

    // MARK: - Rank over time

    private var rankTrendCard: some View {
        let categories = calc.availableCategories(range: range)
        let category = selectedCategory ?? categories.first
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RANK OVER TIME")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                if !categories.isEmpty, let category {
                    Menu {
                        ForEach(categories) { cat in
                            Button(cat.label) { selectedCategory = cat }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(category.label)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                    }
                }
            }

            if let category {
                rankChart(category: category, series: calc.rankSeries(category, range: range))
            } else {
                Text("No ranked entries in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func rankChart(category: InsightCategory, series: [TrendPoint]) -> some View {
        Chart(series) { point in
            AreaMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Rank", point.value)
            )
            .foregroundStyle(category.accent.opacity(0.15).gradient)
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Rank", point.value)
            )
            .foregroundStyle(category.accent)
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Rank", point.value)
            )
            .foregroundStyle(Rank(roundedScore: point.value).color)
        }
        .chartXScale(domain: calc.domainStart(range)...calc.domainEnd)
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let score = value.as(Int.self) {
                        Text(shortRank(score))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 200)
    }

    private func shortRank(_ score: Int) -> String {
        switch score {
        case 5: "EXC"
        case 4: "GOOD"
        case 3: "OK"
        case 2: "BAD"
        default: "AWFUL"
        }
    }

    // MARK: - Selection defaults

    private func ensureSelections() {
        let metrics = calc.availableMetrics(range: range)
        if selectedMetric == nil || !(metrics.contains(selectedMetric!)) {
            selectedMetric = metrics.first
        }
        let categories = calc.availableCategories(range: range)
        if selectedCategory == nil || !(categories.contains(selectedCategory!)) {
            selectedCategory = categories.first
        }
    }
}
