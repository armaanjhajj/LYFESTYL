//
//  HealthHubView.swift
//  LYFESTYL
//
//  The central health surface: everything from Garmin, Hevy and Apple Health in one place.
//
//  Reads top to bottom in order of what matters right now: how recovered you are, what your
//  training load is doing, what the analysis found, today's measured numbers, and then the
//  recent sessions. Anything with nothing to show is simply absent rather than rendered empty.
//

import SwiftUI
import Charts

struct HealthHubView: View {
    @Environment(HealthDataStore.self) private var store
    @Environment(AthleteProfile.self) private var profile
    @Environment(UnitPreference.self) private var units

    @State private var path = NavigationPath()
    @State private var showConnections = false
    @State private var expandedInsightID: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 22) {
                    if store.hasAnyData {
                        readinessSection
                        loadSection
                        insightsSection
                        todaySection
                        volumeSection
                        recentSection
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.refreshAll() }
            .task {
                await store.loadCache()
                await store.pullFromCloud()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavHeaderTitle("TRAIN")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showConnections = true } label: {
                        Image(systemName: store.connectedSourceCount > 0
                              ? "app.connected.to.app.below.fill"
                              : "app.dashed")
                    }
                    .accessibilityLabel("Connections")
                }
            }
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .navigationDestination(for: HealthRoute.self) { route in
                switch route {
                case .workout(let id):        WorkoutDetailView(workoutID: id)
                case .allInsights:           InsightsListView()
                case .activityFeed:          ActivityFeedView()
                case .metric(let metric):    MetricDetailView(metric: metric)
                case .strength:              StrengthDetailView()
                case .loadDetail:            TrainingLoadDetailView()
                }
            }
        }
    }

    // MARK: - Readiness

    @ViewBuilder
    private var readinessSection: some View {
        if let analysis = store.analysis, analysis.readiness.hasSignal {
            let readiness = analysis.readiness
            VStack(alignment: .leading, spacing: 14) {
                HealthSectionHeader("HOW YOU ARE TODAY")

                Text(readiness.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                    .fixedSize(horizontal: false, vertical: true)

                if !readiness.signals.isEmpty {
                    let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(readiness.signals) { signal in
                            Button {
                                path.append(HealthRoute.metric(signal.metric))
                            } label: {
                                signalTile(signal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let state = readiness.formState, let form = readiness.form {
                    Divider().overlay(Color.appTextMuted.opacity(0.2))
                    Button { path.append(HealthRoute.loadDetail) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.label)
                                    .blackCaps(.footnote, tracking: 0.8, color: formColor(state))
                                Text(state.describing)
                                    .font(.caption)
                                    .foregroundStyle(.appTextMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Text(Formatting.signed(form, places: 0))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(formColor(state))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .healthCard()
        }
    }

    private func signalTile(_ signal: ReadinessRead.Signal) -> some View {
        let baseline = signal.baseline
        let favourable = signal.suggestsRecovered == true
        return StatTile(
            label: signal.metric.label,
            value: baseline.latest.map { signal.metric.format($0) } ?? "--",
            unit: signal.metric.displayUnit(weightUnit: units.weightUnit),
            symbolName: signal.metric.symbolName,
            accent: favourable ? Solar.green : Solar.orange,
            context: baseline.delta.map {
                "\(Formatting.signed($0, places: signal.metric.fractionDigits)) vs usual"
            },
            tone: favourable ? .positive : .attention
        )
    }

    private func formColor(_ state: FormState) -> Color {
        switch state {
        case .fresh, .ready:     Solar.green
        case .building:          Solar.blue
        case .strained:          Solar.yellow
        case .overreached:       Solar.orange
        }
    }

    // MARK: - Training load

    @ViewBuilder
    private var loadSection: some View {
        if let analysis = store.analysis, analysis.fitness.count >= 14 {
            Button { path.append(HealthRoute.loadDetail) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HealthSectionHeader(
                        title: "TRAINING LOAD",
                        subtitle: analysis.loadRamp.isEstablished
                            ? nil : "Building a baseline, needs 28 days"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.appTextMuted)
                    }

                    FitnessChart(points: Array(analysis.fitness.suffix(120)))
                        .frame(height: 130)

                    HStack(spacing: 0) {
                        loadStat("FITNESS", analysis.currentFitness, Solar.blue)
                        loadStat("FATIGUE", analysis.fitness.last?.fatigue, Solar.orange)
                        loadStat("FORM", analysis.currentForm, Solar.green, signed: true)
                    }
                }
                .healthCard()
            }
            .buttonStyle(.plain)
        }
    }

    private func loadStat(_ label: String, _ value: Double?, _ color: Color, signed: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value.map { signed ? Formatting.signed($0, places: 0) : Formatting.decimal($0, places: 0) } ?? "--")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsSection: some View {
        let insights = store.visibleInsights
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(
                    title: "WHAT THE DATA SHOWS",
                    subtitle: store.isAnalysing ? "Analysing" : nil
                ) {
                    if insights.count > 3 {
                        Button("See all \(insights.count)") {
                            path.append(HealthRoute.allInsights)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appAccentSecondary)
                    }
                }

                ForEach(insights.prefix(3)) { insight in
                    InsightCard(
                        insight: insight,
                        isExpanded: expandedInsightID == insight.id,
                        onToggle: {
                            withAnimation(.snappy) {
                                expandedInsightID = expandedInsightID == insight.id ? nil : insight.id
                            }
                        },
                        onDismiss: { withAnimation { store.dismissInsight(insight) } }
                    )
                }
            }
        } else if store.isAnalysing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Analysing your data")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            .healthCard()
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todaySection: some View {
        let today = store.snapshot(on: Date()) ?? store.snapshots.last
        if let today, !today.isEmpty {
            let metrics = today.presentMetrics.filter { $0 != .bedtimeConsistency }
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(
                    title: "MEASURED",
                    subtitle: Formatting.relativeDay(today.date)
                ) {
                    SourceChips(sources: today.contributingSources, compact: true)
                }
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(metrics.prefix(8), id: \.self) { metric in
                        if let value = metric.value(from: today) {
                            Button { path.append(HealthRoute.metric(metric)) } label: {
                                StatTile(
                                    label: metric.label,
                                    value: metric.format(value, weightUnit: units.weightUnit),
                                    unit: metric.displayUnit(weightUnit: units.weightUnit),
                                    symbolName: metric.symbolName,
                                    accent: metric.accent,
                                    context: baselineContext(for: metric)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// A short comparison against the personal baseline, when one is established.
    private func baselineContext(for metric: WellnessMetric) -> String? {
        guard let baseline = store.analysis?.baselines[metric], baseline.isEstablished else {
            return nil
        }
        guard baseline.isMeaningfulDeviation, let delta = baseline.delta else {
            return "typical for you"
        }
        return "\(Formatting.signed(delta, places: metric.fractionDigits)) vs usual"
    }

    // MARK: - Volume

    @ViewBuilder
    private var volumeSection: some View {
        if let analysis = store.analysis {
            let trained = analysis.muscleVolume.filter { $0.setsPerWeek > 0 }
            if !trained.isEmpty {
                Button { path.append(HealthRoute.strength) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HealthSectionHeader(
                            title: "WEEKLY SETS BY REGION",
                            subtitle: "Last 28 days"
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.appTextMuted)
                        }
                        MuscleVolumeChart(volumes: analysis.muscleVolume)
                            .frame(height: CGFloat(analysis.muscleVolume.count) * 22 + 20)
                    }
                    .healthCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recent sessions

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(store.workouts.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(title: "RECENT SESSIONS") {
                    Button("See all") { path.append(HealthRoute.activityFeed) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appAccentSecondary)
                }
                ForEach(recent) { workout in
                    Button { path.append(HealthRoute.workout(workout.id)) } label: {
                        WorkoutRow(
                            workout: workout,
                            load: store.analysis?.load(for: workout.id),
                            metric: units.isMetricDistance
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 18) {
            HealthEmptyState(
                symbol: "heart.text.square",
                title: "Bring your training together",
                message: "Connect Apple Health for automatic syncing, add your Hevy account for set-by-set lifting data, and import Garmin FIT files for full session detail.",
                actionTitle: "Connect a source",
                action: { showConnections = true }
            )
        }
        .padding(.top, 40)
    }
}

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
struct WorkoutRow: View {
    let workout: UnifiedWorkout
    var load: TrainingLoadResult?
    var metric: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.sport.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(workout.sport.accent)
                .frame(width: 38, height: 38)
                .background(workout.sport.accent.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(1)
                Text(workout.metricsSummary(metric: metric))
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatting.relativeDay(workout.start))
                    .font(.caption2)
                    .foregroundStyle(.appTextMuted)
                if let load {
                    Text("\(Int(load.load.rounded()))")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                }
            }
        }
        .padding(12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.title), \(workout.metricsSummary(metric: metric)), \(Formatting.relativeDay(workout.start))")
    }
}
