//
//  HealthCharts.swift
//  LYFESTYL
//
//  Navigation routes and the chart and row views the health surfaces share.
//
//  Split out from the dashboard so STYL, the activity feed and the detail screens all draw the
//  same session row and the same fitness curve, rather than each growing its own.
//

import SwiftUI
import Charts

// MARK: - Routes

enum HealthRoute: Hashable {
    case workout(String)
    case allInsights
    case activityFeed
    case metric(WellnessMetric)
    case strength
    case loadDetail

}

// MARK: - Fitness chart

/// Fitness, fatigue and form over time. The classic performance-management view.
struct FitnessChart: View {
    let points: [FitnessPoint]
    var showForm: Bool = true

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Fitness", point.fitness)
                )
                .foregroundStyle(
                    LinearGradient(colors: [Solar.blue.opacity(0.25), Solar.blue.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Fitness", point.fitness),
                    series: .value("Series", "Fitness")
                )
                .foregroundStyle(Solar.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Fatigue", point.fatigue),
                    series: .value("Series", "Fatigue")
                )
                .foregroundStyle(Solar.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(Color.appTextMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Color.appTextMuted)
            }
        }
        .accessibilityLabel("Fitness and fatigue over time")
    }
}

// MARK: - Muscle volume chart

/// Weekly sets per region, with the published dose-response band drawn behind.
struct MuscleVolumeChart: View {
    let volumes: [MuscleVolume]

    var body: some View {
        Chart {
            // The band the hypertrophy literature reports, as context behind the bars.
            RectangleMark(
                xStart: .value("From", MuscleVolume.literatureRange.lowerBound),
                xEnd: .value("To", MuscleVolume.literatureRange.upperBound)
            )
            .foregroundStyle(Solar.green.opacity(0.10))

            ForEach(volumes) { volume in
                BarMark(
                    x: .value("Sets", volume.setsPerWeek),
                    y: .value("Region", volume.system.label)
                )
                .foregroundStyle(volume.system.accent.opacity(volume.setsPerWeek > 0 ? 0.85 : 0.2))
                .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Color.appTextMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextMuted)
                    }
                }
            }
        }
        .accessibilityLabel("Weekly sets by body region against the 10 to 20 set reference range")
    }
}

// MARK: - Workout row

/// One session in a list.
///
/// Deliberately built to the SAME shape as `EntryRowView`: a tinted rounded card, a title, a
/// content line, a divider, then a footer carrying the tag, source and timestamp. A run off a
/// watch and a written note should look like two things in one app rather than two apps, which
/// means they cannot use different row languages just because their data came from elsewhere.
struct WorkoutRow: View {
    let workout: UnifiedWorkout
    var load: TrainingLoadResult?
    var metric: Bool = true
    /// Compact drops the card treatment, for dense dashboard lists.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: workout.sport.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(workout.sport.accent)
                    .frame(width: 30, height: 30)
                    .background(workout.sport.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(workout.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(workout.metricsSummary(metric: metric))
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !compact {
                Divider().overlay(Color.appTextMuted.opacity(0.25))
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background(
            compact ? Color.appSurface : workout.sport.accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.title), \(workout.metricsSummary(metric: metric)), \(Formatting.relativeDay(workout.start))")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: workout.sport.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(workout.sport.accent)
                Text(workout.sport.label.uppercased())
                    .font(.caption2).fontWeight(.bold).tracking(0.4)
                    .foregroundStyle(.appTextEmphasis)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(workout.sport.accent.opacity(0.16), in: Capsule())

            if let load {
                // The training-load figure, with the confidence its method carries.
                Text("\(Int(load.load.rounded()))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.appTextMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: workout.origin.source.symbolName)
                .font(.caption2)
                .foregroundStyle(.appTextMuted)
            Text(timestamp)
                .font(.caption)
                .foregroundStyle(.appTextMuted)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.appTextMuted)
        }
    }

    private var timestamp: String {
        workout.start.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        )
    }
}
