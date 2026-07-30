//
//  HealthDetailViews.swift
//  LYFESTYL
//
//  The secondary health screens: the full insight list, the unified activity feed, a single
//  metric's history, the strength breakdown, and the training-load detail.
//
//  Each one uses native containers (`List`, `NavigationStack`, `.searchable`) rather than
//  rebuilding them, per the project's first-party rule.
//

import SwiftUI
import Charts

// MARK: - All insights

struct InsightsListView: View {
    @Environment(HealthDataStore.self) private var store
    @State private var expandedID: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let coverage = store.analysis?.context.correlationCoverage {
                    Text(coverage.summary)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .healthCard(padding: 12)
                }

                ForEach(grouped, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HealthSectionHeader(group.kind.label)
                        ForEach(group.insights) { insight in
                            InsightCard(
                                insight: insight,
                                isExpanded: expandedID == insight.id,
                                onToggle: {
                                    withAnimation(.snappy) {
                                        expandedID = expandedID == insight.id ? nil : insight.id
                                    }
                                },
                                onDismiss: { withAnimation { store.dismissInsight(insight) } }
                            )
                        }
                    }
                }

                if grouped.isEmpty {
                    HealthEmptyState(
                        symbol: "sparkle.magnifyingglass",
                        title: "Nothing to report yet",
                        message: "Insights appear once there is enough history for them to be trustworthy. Most need two to four weeks."
                    )
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var grouped: [(kind: InsightKind, insights: [HealthInsight])] {
        store.visibleInsights.groupedByKind
    }
}

// MARK: - Activity feed

struct ActivityFeedView: View {
    @Environment(HealthDataStore.self) private var store
    @Environment(UnitPreference.self) private var units

    @State private var searchText = ""
    @State private var selectedFamily: SportFamily?

    var body: some View {
        List {
            if !filtered.isEmpty {
                ForEach(grouped, id: \.month) { group in
                    Section {
                        ForEach(group.workouts) { workout in
                            NavigationLink(value: HealthRoute.workout(workout.id)) {
                                WorkoutRow(
                                    workout: workout,
                                    load: store.analysis?.load(for: workout.id),
                                    metric: units.isMetricDistance,
                                    compact: true
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                            .blackCaps(.caption, tracking: 0.8, color: .appTextMuted)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .searchable(text: $searchText, prompt: "Search sessions")
        .overlay {
            if filtered.isEmpty {
                HealthEmptyState(
                    symbol: "figure.run",
                    title: searchText.isEmpty ? "No sessions yet" : "No matches",
                    message: searchText.isEmpty
                        ? "Connect a source to bring your training in."
                        : "Try a different search."
                )
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All sports") { selectedFamily = nil }
                    Divider()
                    ForEach(SportFamily.allCases, id: \.self) { family in
                        Button {
                            selectedFamily = family
                        } label: {
                            Label(family.label.capitalized,
                                  systemImage: selectedFamily == family ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: selectedFamily == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by sport")
            }
        }
    }

    private var filtered: [UnifiedWorkout] {
        store.workouts.filter { workout in
            if let selectedFamily, workout.family != selectedFamily { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return workout.title.lowercased().contains(needle)
                || workout.sport.label.lowercased().contains(needle)
                || (workout.strength?.exercises.contains {
                    $0.name.lowercased().contains(needle)
                } ?? false)
        }
    }

    private var grouped: [(month: Date, workouts: [UnifiedWorkout])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { workout in
            calendar.dateInterval(of: .month, for: workout.start)?.start ?? workout.day
        }
        .map { (month: $0.key, workouts: $0.value.sorted { $0.start > $1.start }) }
        .sorted { $0.month > $1.month }
    }
}

// MARK: - Metric detail

struct MetricDetailView: View {
    let metric: WellnessMetric

    @Environment(HealthDataStore.self) private var store
    @Environment(UnitPreference.self) private var units
    @State private var rangeDays = 90

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if points.count >= 3 {
                    chartCard
                    if let baseline = store.analysis?.baselines[metric] {
                        baselineCard(baseline)
                    }
                    distributionCard
                } else {
                    HealthEmptyState(
                        symbol: metric.symbolName,
                        title: "Not enough \(metric.label.lowercased()) data",
                        message: "This needs at least a few days of readings before it can show a trend."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle(metric.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Range", selection: $rangeDays) {
                    Text("30D").tag(30)
                    Text("90D").tag(90)
                    Text("1Y").tag(365)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

    private var points: [(date: Date, value: Double)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date()
        return store.snapshots
            .filter { $0.date >= cutoff }
            .compactMap { snapshot in
                guard let value = metric.value(from: snapshot) else { return nil }
                return (snapshot.date, value)
            }
            .sorted { $0.date < $1.date }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader(
                titled: metric.label.uppercased(),
                subtitle: "\(points.count) readings"
            ) {
                if let latest = points.last {
                    Text(metric.format(latest.value, includeUnit: true, weightUnit: units.weightUnit))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                }
            }
            Chart {
                if let baseline = store.analysis?.baselines[metric], baseline.isEstablished {
                    RuleMark(y: .value("Usual", baseline.center))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.appTextMuted.opacity(0.6))
                        .annotation(position: .top, alignment: .leading) {
                            Text("your usual")
                                .font(.caption2)
                                .foregroundStyle(Color.appTextMuted)
                        }
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.label, point.value))
                        .foregroundStyle(metric.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(points, id: \.date) { point in
                    PointMark(x: .value("Date", point.date), y: .value(metric.label, point.value))
                        .foregroundStyle(metric.accent.opacity(0.5))
                        .symbolSize(14)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.appTextMuted)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.12))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2).foregroundStyle(Color.appTextMuted)
                }
            }
            .frame(height: 190)
        }
        .healthCard()
    }

    private func baselineCard(_ baseline: MetricBaseline) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("YOUR BASELINE")
            EvidenceList(evidence: [
                InsightEvidence("Your usual",
                                metric.format(baseline.center, includeUnit: true, weightUnit: units.weightUnit),
                                context: "median of \(baseline.sampleCount) days"),
                InsightEvidence("Day-to-day spread",
                                metric.format(baseline.spread, includeUnit: true, weightUnit: units.weightUnit),
                                context: "robust, so one odd day does not widen it"),
                InsightEvidence("Worth noticing past",
                                metric.format(baseline.smallestWorthwhileChange, includeUnit: true, weightUnit: units.weightUnit),
                                context: "smaller moves are inside your normal noise"),
            ])
            if baseline.analysedOnLogScale {
                Text("Heart-rate variability is analysed on a logarithmic scale, since its day-to-day swing grows with its level. The figures above are converted back to milliseconds.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let trend = baseline.trend, trend.isSignificant {
                Divider().overlay(Color.appTextMuted.opacity(0.2))
                HStack(spacing: 8) {
                    Image(systemName: trend.direction == .increasing ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(metric.accent)
                    Text("Trending \(trend.direction == .increasing ? "up" : "down") over this window")
                        .font(.caption)
                        .foregroundStyle(.appText)
                    Spacer()
                    Text("p = \(Formatting.decimal(trend.pValue, places: 3))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.appTextMuted)
                }
            }
        }
        .healthCard()
    }

    private var distributionCard: some View {
        let values = points.map(\.value)
        return VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("RANGE")
            HStack(spacing: 0) {
                rangeStat("LOWEST", values.min())
                rangeStat("MEDIAN", Stats.median(values))
                rangeStat("HIGHEST", values.max())
            }
        }
        .healthCard()
    }

    private func rangeStat(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(value.map { metric.format($0, weightUnit: units.weightUnit) } ?? "--")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.appTextEmphasis)
            Text(label)
                .font(.caption2).fontWeight(.bold).tracking(0.5)
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Strength detail

struct StrengthDetailView: View {
    @Environment(HealthDataStore.self) private var store
    @Environment(UnitPreference.self) private var units

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let analysis = store.analysis, !analysis.muscleVolume.isEmpty {
                    volumeCard(analysis)
                    balanceCard(analysis)
                    exercisesCard(analysis)
                } else {
                    HealthEmptyState(
                        symbol: "dumbbell.fill",
                        title: "No lifting data yet",
                        message: "Connect Hevy, or import a Garmin strength session, to see volume by muscle and how each lift is trending."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func volumeCard(_ analysis: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader(
                "WEEKLY SETS BY REGION",
                subtitle: "Last 28 days, against the 10 to 20 set reference"
            )
            MuscleVolumeChart(volumes: analysis.muscleVolume)
                .frame(height: CGFloat(analysis.muscleVolume.count) * 24 + 24)
            VStack(spacing: 8) {
                ForEach(analysis.muscleVolume) { volume in
                    HStack(spacing: 8) {
                        Circle().fill(volume.system.accent).frame(width: 8, height: 8)
                        Text(volume.system.label.capitalized)
                            .font(.caption)
                            .foregroundStyle(.appText)
                        Spacer()
                        Text(volume.standing.label)
                            .font(.caption2)
                            .foregroundStyle(.appTextMuted)
                        Text("\(Formatting.decimal(volume.setsPerWeek, places: 1))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
        .healthCard()
    }

    @ViewBuilder
    private func balanceCard(_ analysis: AnalysisResult) -> some View {
        let usable = analysis.context.balanceRatios.filter(\.hasEnoughData)
        if !usable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader("BALANCE")
                ForEach(usable) { ratio in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(ratio.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                            Spacer()
                            if let value = ratio.ratio {
                                Text(Formatting.decimal(value, places: 2))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(ratio.isBalanced == true ? Solar.green : Solar.orange)
                            }
                        }
                        Text("\(ratio.numeratorLabel) \(Formatting.decimal(ratio.numeratorSets, places: 0)) sets, \(ratio.denominatorLabel) \(Formatting.decimal(ratio.denominatorSets, places: 0)) sets")
                            .font(.caption)
                            .foregroundStyle(.appTextMuted)
                        Text(ratio.source)
                            .font(.caption2)
                            .foregroundStyle(.appTextMuted)
                    }
                    if ratio.id != usable.last?.id {
                        Divider().overlay(Color.appTextMuted.opacity(0.15))
                    }
                }
            }
            .healthCard()
        }
    }

    @ViewBuilder
    private func exercisesCard(_ analysis: AnalysisResult) -> some View {
        let tracked = analysis.exerciseProgress.filter { $0.sessionCount >= 3 }.prefix(12)
        if !tracked.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader("MOVEMENTS", subtitle: "Estimated one-rep max where it applies")
                ForEach(Array(tracked)) { exercise in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                                .lineLimit(1)
                            Text("\(exercise.sessionCount) session\(exercise.sessionCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.appTextMuted)
                        }
                        Spacer(minLength: 6)
                        if let current = exercise.currentOneRepMax {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Formatting.weight(kilograms: current, unit: units.weightUnit))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.appTextEmphasis)
                                if let trend = exercise.oneRepMaxTrend, trend.test.isSignificant {
                                    Text(trend.test.direction == .increasing ? "climbing" : "falling")
                                        .font(.caption2)
                                        .foregroundStyle(trend.test.direction == .increasing ? Solar.green : Solar.orange)
                                }
                            }
                        }
                    }
                    if exercise.id != tracked.last?.id {
                        Divider().overlay(Color.appTextMuted.opacity(0.15))
                    }
                }
            }
            .healthCard()
        }
    }
}

// MARK: - Training load detail

struct TrainingLoadDetailView: View {
    @Environment(HealthDataStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let analysis = store.analysis, analysis.fitness.count >= 7 {
                    chartCard(analysis)
                    rampCard(analysis)
                    weeksCard(analysis)
                    if let intensity = analysis.context.intensity, intensity.hasEnoughData {
                        intensityCard(intensity)
                    }
                    methodCard(analysis)
                } else {
                    HealthEmptyState(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Not enough history",
                        message: "The fitness model uses a 42-day average, so it needs about six weeks before it means much."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Training Load")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chartCard(_ analysis: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader(
                "FITNESS AND FATIGUE",
                subtitle: "42-day and 7-day weighted averages of daily load"
            )
            FitnessChart(points: Array(analysis.fitness.suffix(180)))
                .frame(height: 190)
            HStack(spacing: 14) {
                legend("Fitness", Solar.blue)
                legend("Fatigue", Solar.orange)
            }
        }
        .healthCard()
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 3)
            Text(label).font(.caption2).foregroundStyle(.appTextMuted)
        }
    }

    private func rampCard(_ analysis: AnalysisResult) -> some View {
        let ramp = analysis.loadRamp
        return VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("LOAD RAMP", subtitle: ramp.band?.label)
            EvidenceList(evidence: [
                InsightEvidence("Recent (7 day)", Formatting.decimal(ramp.acute, places: 0)),
                InsightEvidence("Baseline (28 day)", Formatting.decimal(ramp.chronic, places: 0)),
                InsightEvidence("Ratio", ramp.ratio.map { Formatting.decimal($0, places: 2) } ?? "--"),
                InsightEvidence("Uncoupled ratio",
                                ramp.uncoupledRatio.map { Formatting.decimal($0, places: 2) } ?? "--",
                                context: "last 7 days vs the 21 before"),
            ])
            Text("The acute-to-chronic ratio is useful for spotting a sharp change, but the popular idea that a specific value predicts injury has been seriously questioned, partly because the standard construction includes the recent window inside its own baseline. The uncoupled figure above avoids that.")
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }

    private func weeksCard(_ analysis: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader("WEEKLY LOAD", subtitle: "Last 12 weeks")
            Chart {
                ForEach(analysis.weeks.suffix(12)) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Load", week.totalLoad)
                    )
                    .foregroundStyle(Solar.blue.opacity(0.8))
                    .cornerRadius(3)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.15))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.appTextMuted)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2).foregroundStyle(Color.appTextMuted)
                }
            }
            .frame(height: 140)
        }
        .healthCard()
    }

    private func intensityCard(_ intensity: FitnessModel.IntensityDistribution) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader(
                "INTENSITY DISTRIBUTION",
                subtitle: "Where your heart-rate time goes"
            )
            HStack(spacing: 16) {
                MetricRing(segments: [
                    (intensity.easyFraction, Solar.cyan),
                    (intensity.moderateFraction, Solar.yellow),
                    (intensity.hardFraction, Solar.red),
                ], size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    intensityRow("Easy", intensity.easyFraction, Solar.cyan)
                    intensityRow("Moderate", intensity.moderateFraction, Solar.yellow)
                    intensityRow("Hard", intensity.hardFraction, Solar.red)
                }
            }
            Text("Studies of well-trained endurance athletes consistently find around 80 percent of their time at low intensity. That is a description of what they do, not a rule.")
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }

    private func intensityRow(_ label: String, _ fraction: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.appText)
            Spacer(minLength: 10)
            Text(Formatting.percent(fraction: fraction))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.appTextEmphasis)
        }
    }

    private func methodCard(_ analysis: AnalysisResult) -> some View {
        // Show how sessions are actually being scored, since it drives how much the whole
        // chart can be trusted.
        let counts = Dictionary(grouping: analysis.context.loads.values, by: \.method)
            .mapValues(\.count)
            .sorted { $0.key > $1.key }

        return VStack(alignment: .leading, spacing: 10) {
            HealthSectionHeader("HOW SESSIONS ARE SCORED")
            EvidenceList(evidence: counts.map { method, count in
                InsightEvidence(method.label.capitalized, "\(count) session\(count == 1 ? "" : "s")")
            })
            Text("Load is scored from the best signal each session carried. Power against threshold power is the most reliable, then grade-adjusted pace, then heart rate, then perceived effort. Duration alone is a deliberately conservative last resort.")
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }
}
