//
//  WorkoutDetailView.swift
//  LYFESTYL
//
//  One session in full.
//
//  What is shown depends entirely on what the source actually recorded, and the screen says so
//  when something is missing rather than drawing an empty chart. A Garmin ride read from Apple
//  Health has no heart-rate series, so it shows its summary and an explanation; the same ride
//  imported from its .fit file shows everything.
//

import SwiftUI
import Charts

struct WorkoutDetailView: View {
    let workoutID: String

    @Environment(HealthDataStore.self) private var store
    @Environment(UnitPreference.self) private var units

    private var workout: UnifiedWorkout? { store.workout(id: workoutID) }
    private var load: TrainingLoadResult? { store.analysis?.load(for: workoutID) }
    private var zones: ZoneDistribution? { store.analysis?.zones(for: workoutID) }

    var body: some View {
        ScrollView {
            if let workout {
                VStack(spacing: 20) {
                    header(workout)
                    summaryGrid(workout)
                    if let load { loadCard(load, workout: workout) }
                    if let zones { zoneCard(zones) }
                    seriesSection(workout)
                    if let strength = workout.strength { strengthCard(strength) }
                    if let route = workout.route, !route.isEmpty { routeCard(route) }
                    provenanceCard(workout)
                }
                .padding(20)
            } else {
                HealthEmptyState(
                    symbol: "questionmark.folder",
                    title: "Session not found",
                    message: "It may have been removed from its source."
                )
                .padding(.top, 60)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(workout?.sport.label ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func header(_ workout: UnifiedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: workout.sport.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(workout.sport.accent)
                    .frame(width: 50, height: 50)
                    .background(workout.sport.accent.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.appTextEmphasis)
                        .lineLimit(2)
                    Text(Formatting.dayAndTime(workout.start))
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                }
                Spacer(minLength: 0)
            }
            if let notes = workout.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .healthCard()
    }

    // MARK: - Summary

    private func summaryGrid(_ workout: UnifiedWorkout) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "Duration",
                     value: Formatting.duration(workout.movingSeconds),
                     symbolName: "clock", accent: Solar.blue)

            if let distance = workout.distanceMeters, workout.family.hasDistance {
                StatTile(label: "Distance",
                         value: Formatting.distance(distance, metric: units.isMetricDistance, includeUnit: false),
                         unit: Formatting.distanceUnit(metric: units.isMetricDistance),
                         symbolName: "point.topleft.down.to.point.bottomright.curvepath",
                         accent: Solar.cyan)
            }
            if let pace = workout.paceSecondsPerKm,
               workout.discipline == .running || workout.discipline == .walking {
                StatTile(label: "Pace",
                         value: Formatting.pace(secondsPerKm: pace, metric: units.isMetricDistance, includeUnit: false),
                         unit: "/\(Formatting.distanceUnit(metric: units.isMetricDistance))",
                         symbolName: "speedometer", accent: Solar.green)
            } else if let speed = workout.effectiveSpeedMps, workout.discipline == .cycling {
                StatTile(label: "Speed",
                         value: Formatting.speed(speed, metric: units.isMetricDistance),
                         symbolName: "speedometer", accent: Solar.green)
            }
            if let hr = workout.averageHeartRate {
                StatTile(label: "Avg heart rate", value: "\(Int(hr.rounded()))", unit: "bpm",
                         symbolName: "heart.fill", accent: Solar.magenta,
                         context: workout.maxHeartRate.map { "max \(Int($0.rounded()))" })
            }
            if let power = workout.averagePowerWatts {
                StatTile(label: "Avg power", value: "\(Int(power.rounded()))", unit: "W",
                         symbolName: "bolt.fill", accent: Solar.yellow,
                         context: workout.normalizedPowerWatts.map {
                             "normalized \(Int($0.rounded()))"
                         })
            }
            if let energy = workout.activeEnergyKcal {
                StatTile(label: "Energy", value: Formatting.count(energy), unit: "kcal",
                         symbolName: "flame.fill", accent: Solar.orange)
            }
            if let gain = workout.elevationGainMeters, gain > 1 {
                StatTile(label: "Elevation",
                         value: Formatting.elevation(gain, metric: units.isMetricDistance),
                         symbolName: "mountain.2.fill", accent: Solar.violet)
            }
            if let cadence = workout.averageCadence {
                StatTile(label: "Cadence", value: "\(Int(cadence.rounded()))",
                         unit: workout.discipline == .cycling ? "rpm" : "spm",
                         symbolName: "metronome", accent: Solar.cyan)
            }
            if let decoupling = workout.decouplingPercent {
                StatTile(
                    label: "Decoupling",
                    value: Formatting.decimal(decoupling, places: 1), unit: "%",
                    symbolName: "arrow.down.right", accent: Solar.blue,
                    context: decoupling > TrainingLoad.decouplingConcernThreshold
                        ? "above the usual 5% mark" : "held steady",
                    tone: decoupling > TrainingLoad.decouplingConcernThreshold ? .attention : .positive
                )
            }
            if let effort = workout.perceivedEffort {
                StatTile(label: "Perceived effort", value: Formatting.decimal(effort, places: 1),
                         unit: "/10", symbolName: "gauge.with.needle", accent: Solar.orange)
            }
        }
    }

    // MARK: - Load

    private func loadCard(_ load: TrainingLoadResult, workout: UnifiedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("TRAINING LOAD")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(load.load.rounded()))")
                    .font(.largeTitle.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.appTextEmphasis)
                Text("points")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                Spacer()
                if let intensity = load.intensityFactor {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Formatting.decimal(intensity, places: 2))
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                        Text("INTENSITY")
                            .font(.caption2).fontWeight(.bold).tracking(0.5)
                            .foregroundStyle(.appTextMuted)
                    }
                }
            }
            // Say plainly how this number was arrived at, since the methods differ a lot in
            // how much they can be trusted.
            Text(loadExplanation(load))
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }

    private func loadExplanation(_ load: TrainingLoadResult) -> String {
        var text: String
        switch load.method {
        case .powerTSS:
            text = "Computed from your power file against your threshold power, which is the most reliable way to score a session."
        case .paceStress:
            text = "Computed from grade-adjusted pace against your threshold pace, using Minetti's measured cost of running on a gradient."
        case .swimStress:
            text = "Computed from swim pace against your threshold pace."
        case .heartRateTRIMP:
            text = "Computed from heart rate using the exponential TRIMP weighting, then scaled so one hour at threshold is 100 points."
        case .zoneTRIMP:
            text = "Computed from time in each heart-rate zone."
        case .sessionRPE:
            text = "Computed from perceived effort times duration, since this session carried no usable heart rate or power."
        case .durationOnly:
            text = "Estimated from duration alone, because nothing else was recorded. Deliberately conservative, and the weakest figure here."
        }
        if load.usedEstimatedAnchor {
            text += " One of the personal numbers behind this is an estimate rather than your own measurement, so set it in your profile for a sharper figure."
        }
        return text
    }

    // MARK: - Zones

    private func zoneCard(_ zones: ZoneDistribution) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader(
                "HEART-RATE ZONES",
                subtitle: "Boundaries from your own reserve"
            )
            ZoneBar(distribution: zones, height: 14)
            VStack(spacing: 6) {
                ForEach(0..<ZoneDistribution.zoneCount, id: \.self) { zone in
                    let seconds = zones.seconds[zone]
                    if seconds > 0 {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(ZoneBar.zoneColors[zone])
                                .frame(width: 8, height: 8)
                            Text("Zone \(zone + 1)")
                                .font(.caption)
                                .foregroundStyle(.appText)
                            Spacer()
                            Text(Formatting.durationWords(seconds))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.appTextEmphasis)
                            Text(Formatting.percent(fraction: zones.fraction(zone: zone)))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.appTextMuted)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .healthCard()
    }

    // MARK: - Series

    @ViewBuilder
    private func seriesSection(_ workout: UnifiedWorkout) -> some View {
        if let heartRate = workout.heartRateSeries, heartRate.count >= 5 {
            seriesCard("HEART RATE", series: heartRate, unit: "bpm", accent: Solar.magenta)
        }
        if let power = workout.powerSeries, power.count >= 5 {
            seriesCard("POWER", series: power, unit: "W", accent: Solar.yellow)
        }
        if let speed = workout.speedSeries, speed.count >= 5, workout.family.hasDistance {
            seriesCard("SPEED", series: speed, unit: "m/s", accent: Solar.green)
        }
        if let altitude = workout.altitudeSeries, altitude.count >= 5 {
            seriesCard("ELEVATION", series: altitude, unit: "m", accent: Solar.violet)
        }
        // Explain the absence rather than leaving a gap.
        if workout.heartRateSeries == nil, workout.family == .endurance {
            VStack(alignment: .leading, spacing: 8) {
                HealthSectionHeader("NO DETAILED SAMPLES")
                Text(workout.origin.source == .garmin
                     ? "Garmin sends only a summary of each workout to Apple Health, without the GPS track or second-by-second heart rate. Import this session's .fit file to unlock heart-rate zones, aerobic decoupling and grade-adjusted pace for it."
                     : "This session arrived without a sample series, so the within-session analyses are not available for it.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .healthCard()
        }
    }

    private func seriesCard(_ title: String, series: MetricSeries, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader(titled: title) {
                if let mean = series.mean {
                    Text("avg \(Formatting.decimal(mean, places: 0)) \(unit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.appTextMuted)
                }
            }
            Chart {
                ForEach(Array(series.values.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", series.offsets[index]),
                        y: .value(title, value)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.12))
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(Formatting.duration(seconds))
                                .font(.caption2)
                                .foregroundStyle(Color.appTextMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.12))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Color.appTextMuted)
                }
            }
            .frame(height: 130)
        }
        .healthCard()
        .accessibilityLabel("\(title) over the session")
    }

    // MARK: - Strength

    private func strengthCard(_ strength: StrengthSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HealthSectionHeader(titled: "EXERCISES", subtitle: strength.countSummary) {
                if let volume = strength.volumeLoadKg {
                    Text(Formatting.weight(kilograms: volume, unit: units.weightUnit))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextMuted)
                }
            }
            ForEach(strength.exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.appTextEmphasis)
                        Spacer(minLength: 4)
                        if let oneRM = OneRepMax.best(in: exercise.sets) {
                            Text("e1RM \(Formatting.weight(kilograms: oneRM, unit: units.weightUnit))")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.appTextMuted)
                        }
                    }
                    Text(exercise.summary(unit: units.weightUnit))
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                    if !exercise.systems.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(exercise.systems, id: \.self) { system in
                                Text(system.label)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(system.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(system.accent.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if exercise.id != strength.exercises.last?.id {
                    Divider().overlay(Color.appTextMuted.opacity(0.15))
                }
            }
        }
        .healthCard()
    }

    // MARK: - Route

    private func routeCard(_ route: RouteSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("ROUTE", subtitle: "\(route.pointCount) points")
            // A normalized path drawing rather than a map: it shows the shape of the session
            // without needing map credentials or a network round trip.
            RouteShape(route: route)
                .stroke(Solar.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(height: 170)
                .padding(6)
                .background(Color.appBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .healthCard()
    }

    // MARK: - Provenance

    private func provenanceCard(_ workout: UnifiedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthSectionHeader("SOURCE")
            HStack(spacing: 6) {
                SourceChip(source: workout.origin.source)
                ForEach(workout.mergedSources, id: \.uniqueKey) { ref in
                    SourceChip(source: ref.source)
                }
            }
            if !workout.mergedSources.isEmpty {
                Text("More than one source recorded this session. The richest version is shown, and nothing measured by the others was discarded.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .healthCard()
    }
}

// MARK: - Route shape

/// Draws a GPS track normalized into the available space, with latitude scaled so the shape is
/// not distorted at higher latitudes.
struct RouteShape: Shape {
    let route: RouteSummary

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard route.pointCount >= 2 else { return path }

        let latSpan = max(route.maxLatitude - route.minLatitude, 0.00001)
        let lonSpan = max(route.maxLongitude - route.minLongitude, 0.00001)
        // A degree of longitude is shorter than a degree of latitude away from the equator, by
        // the cosine of the latitude. Without this correction routes look stretched east-west.
        let midLatitude = (route.maxLatitude + route.minLatitude) / 2
        let lonScale = cos(midLatitude * .pi / 180)
        let effectiveLonSpan = lonSpan * lonScale

        let scale = min(rect.width / effectiveLonSpan, rect.height / latSpan)
        let drawWidth = effectiveLonSpan * scale
        let drawHeight = latSpan * scale
        let originX = rect.midX - drawWidth / 2
        let originY = rect.midY - drawHeight / 2

        for index in 0..<route.pointCount {
            let x = originX + (route.longitudes[index] - route.minLongitude) * lonScale * scale
            // Latitude increases northward, screen y increases downward.
            let y = originY + (route.maxLatitude - route.latitudes[index]) * scale
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
