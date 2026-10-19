//
//  MetricDetailView.swift
//  LYFESTYL
//
//  One nutrient over time, like a Health data page: a W / M / 6M / Y switch,
//  the average (or the bar you're touching) called out above a bar chart with
//  the goal as a dashed line.
//

import Charts
import SwiftUI

struct MetricDetailView: View {
    let macro: Macro
    let days: [DayTotal]

    @Environment(GoalStore.self) private var goalStore
    @State private var span: Span = .week
    @State private var selected: Date?

    enum Span: String, CaseIterable, Identifiable {
        case week = "W", month = "M", sixMonths = "6M", year = "Y"
        var id: String { rawValue }

        /// Days covered, and the size of each bar.
        var length: (days: Int, bar: Calendar.Component) {
            switch self {
            case .week:      (7, .day)
            case .month:     (30, .day)
            case .sixMonths: (182, .weekOfYear)
            case .year:      (365, .month)
            }
        }
    }

    struct Point: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let goal = goalStore.goals[macro]
        let points = Self.points(days: days, macro: macro, span: span)
        let average = points.isEmpty ? 0 : points.map(\.value).reduce(0, +) / Double(points.count)
        let picked = selected.flatMap { date in
            points.first { Calendar.current.isDate($0.date, equalTo: date, toGranularity: span.length.bar) }
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                callout(picked: picked, average: average, points: points)

                chart(points: points, goal: goal, picked: picked)
                    .frame(height: 260)

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(.appBackground)
        .capsNavigationTitle(macro.name)
        .onChange(of: span) { selected = nil }
        .sensoryFeedback(.selection, trigger: picked?.date)
    }

    // MARK: - Pieces

    private func callout(picked: Point?, average: Double, points: [Point]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(picked == nil ? "DAILY AVERAGE" : (span.length.bar == .day ? "TOTAL" : "DAILY AVERAGE"))
                .font(.caption.weight(.black))
                .tracking(0.5)
                .foregroundStyle(.appTextMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let value = picked?.value ?? average
                Text(points.isEmpty ? "--" : (macro == .calories ? Formatting.calories(value) : Formatting.grams(value, includeUnit: false)))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.appTextEmphasis)
                    .contentTransition(.numericText(value: value))
                Text(macro.unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
            .monospacedDigit()
            Text(picked.map { label(for: $0.date) } ?? rangeLabel(points))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.appTextMuted)
        }
        .animation(.snappy, value: picked)
    }

    private func chart(points: [Point], goal: Double, picked: Point?) -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: span.length.bar),
                    y: .value(macro.name, point.value)
                )
                .cornerRadius(3)
                .foregroundStyle(picked == nil || picked == point ? macro.accent : macro.accent.opacity(0.35))
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(Color.appTextMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            if let picked {
                RuleMark(x: .value("Selected", picked.date, unit: span.length.bar))
                    .foregroundStyle(Color.appTextMuted.opacity(0.5))
            }
        }
        .chartXSelection(value: $selected)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.2))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(axisLabel(date)) }
                }
            }
        }
        .accessibilityLabel("\(macro.name) chart")
    }

    // MARK: - Data

    /// Bars for the span: daily totals for W and M, daily averages per week
    /// for 6M and per month for Y. Days with nothing logged don't count.
    static func points(days: [DayTotal], macro: Macro, span: Span) -> [Point] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(span.length.days - 1), to: today) else { return [] }
        let inRange = days.filter { $0.day >= start && $0.mealCount > 0 }

        switch span.length.bar {
        case .day:
            return inRange.map { Point(date: $0.day, value: $0.nutrition[macro]) }.sorted { $0.date < $1.date }
        default:
            let groups = Dictionary(grouping: inRange) {
                calendar.dateInterval(of: span.length.bar, for: $0.day)?.start ?? $0.day
            }
            return groups.map { start, days in
                Point(date: start, value: days.map { $0.nutrition[macro] }.reduce(0, +) / Double(days.count))
            }
            .sorted { $0.date < $1.date }
        }
    }

    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(span.length.days - 1), to: today) ?? today
        let first = calendar.dateInterval(of: span.length.bar, for: start)?.start ?? start
        let end = calendar.dateInterval(of: span.length.bar, for: today)?.end ?? today
        return first...end
    }

    private var xAxisValues: AxisMarkValues {
        switch span {
        case .week:      .stride(by: .day)
        case .month:     .stride(by: .day, count: 7)
        case .sixMonths: .stride(by: .month)
        case .year:      .stride(by: .month)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch span {
        case .week:      date.formatted(.dateTime.weekday(.narrow))
        case .month:     date.formatted(.dateTime.day())
        case .sixMonths: date.formatted(.dateTime.month(.abbreviated))
        case .year:      date.formatted(.dateTime.month(.narrow))
        }
    }

    private func label(for date: Date) -> String {
        switch span.length.bar {
        case .day:        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .weekOfYear: "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
        default:          date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func rangeLabel(_ points: [Point]) -> String {
        guard let first = points.first?.date else { return "Nothing logged yet" }
        let last = points.last?.date ?? first
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return first == last ? first.formatted(style) : "\(first.formatted(style)) to \(last.formatted(style.year()))"
    }


}
