//
//  StylView.swift
//  LYFESTYL
//
//  The STYL surface: ONE health dashboard for everything the app knows.
//
//  There is no separate place for "synced" and "logged" data. Whether a session came from a
//  watch, from Hevy, or from the logger in this app, it is scored and analysed the same way and
//  appears in the same figures here. The journal adds what training data cannot see, which is
//  nutrition, mind and social, so those sit alongside rather than in a different screen.
//
//  Reads top to bottom in order of what matters right now: how recovered you are, what your
//  training load is doing, what the analysis found, today's measured numbers, what you have
//  been logging, weekly volume, and recent sessions.
//
//  Honesty rule (CLAUDE.md): every figure shown is measured or computed from measured data, and
//  is attributed to the source it came from.
//

import SwiftUI
import Charts

struct StylView: View {
    @Environment(JournalStore.self) private var store
    @Environment(HealthDataStore.self) private var healthData
    @Environment(UnitPreference.self) private var units

    @State private var path = NavigationPath()
    @State private var showAccount = false
    @State private var showConnections = false
    @State private var showSuggestion = false
    @State private var expandedInsightID: String?

    private var calc: TrendCalculator { TrendCalculator(entries: store.entries) }
    private var hasAnySignal: Bool { healthData.hasAnyData || store.hasAnyEntries }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 22) {
                    if hasAnySignal {
                        readinessSection
                        loadSection
                        insightsSection
                        todaySection
                        volumeSection
                        categoryActivityCard
                        recentSection
                        trendsLink
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await store.refresh()
                await healthData.refreshAll()
            }
            .task {
                await healthData.loadCache()
                await healthData.pullFromCloud()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavHeaderTitle("STYL") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showConnections = true } label: {
                        Image(systemName: healthData.connectedSourceCount > 0
                              ? "app.connected.to.app.below.fill" : "app.dashed")
                    }
                    .accessibilityLabel("Connections")
                    Button { showAccount = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .sheet(isPresented: $showAccount) { ProfileView() }
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .sheet(isPresented: $showSuggestion) {
                AIChatView(
                    contextSummary: volumeSummaryForModel(),
                    initialPrompt: "Suggest a balanced session for me based on what I have trained recently."
                )
            }
            .navigationDestination(for: UUID.self) { EntryDetailView(entryID: $0) }
            .navigationDestination(for: HealthRoute.self) { route in
                switch route {
                case .workout(let id):     WorkoutDetailView(workoutID: id)
                case .allInsights:         InsightsListView()
                case .activityFeed:        ActivityFeedView()
                case .metric(let metric):  MetricDetailView(metric: metric)
                case .strength:            StrengthDetailView()
                case .loadDetail:          TrainingLoadDetailView()
                }
            }
        }
    }

    // MARK: - Readiness

    @ViewBuilder
    private var readinessSection: some View {
        if let analysis = healthData.analysis, analysis.readiness.hasSignal {
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
                            Button { path.append(HealthRoute.metric(signal.metric)) } label: {
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
        case .fresh, .ready: Solar.green
        case .building:      Solar.blue
        case .strained:      Solar.yellow
        case .overreached:   Solar.orange
        }
    }

    // MARK: - Training load

    @ViewBuilder
    private var loadSection: some View {
        if let analysis = healthData.analysis, analysis.fitness.count >= 14 {
            Button { path.append(HealthRoute.loadDetail) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HealthSectionHeader(
                        titled: "TRAINING LOAD",
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
                .font(.caption2).fontWeight(.bold).tracking(0.5)
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsSection: some View {
        let insights = healthData.visibleInsights
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(
                    titled: "WHAT THE DATA SHOWS",
                    subtitle: healthData.isAnalysing ? "Analysing" : nil
                ) {
                    if insights.count > 3 {
                        Button("See all \(insights.count)") { path.append(HealthRoute.allInsights) }
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
                        onDismiss: { withAnimation { healthData.dismissInsight(insight) } }
                    )
                }
            }
        } else if healthData.isAnalysing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Analysing your data")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            .healthCard()
        }
    }

    // MARK: - Measured today

    @ViewBuilder
    private var todaySection: some View {
        let today = healthData.snapshot(on: Date()) ?? healthData.snapshots.last
        if let today, !today.isEmpty {
            let metrics = today.presentMetrics.filter { $0 != .bedtimeConsistency }
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(
                    titled: "MEASURED",
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

    private func baselineContext(for metric: WellnessMetric) -> String? {
        guard let baseline = healthData.analysis?.baselines[metric], baseline.isEstablished else {
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
        if let analysis = healthData.analysis,
           analysis.muscleVolume.contains(where: { $0.setsPerWeek > 0 }) {
            VStack(alignment: .leading, spacing: 12) {
                Button { path.append(HealthRoute.strength) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HealthSectionHeader(
                            titled: "WEEKLY SETS BY REGION",
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
                SuggestSessionButton { showSuggestion = true }
            }
        }
    }

    /// A neutral summary of recent volume for the on-device coach.
    private func volumeSummaryForModel() -> String {
        guard let volumes = healthData.analysis?.muscleVolume, !volumes.isEmpty else {
            return "I have not logged any resistance training recently."
        }
        var lines = ["Weekly sets by region over the last 28 days:"]
        for volume in volumes {
            let name = volume.system.label.capitalized
            if volume.setsPerWeek > 0 {
                let when: String
                switch volume.daysSinceLastTrained {
                case 0: when = "today"
                case 1: when = "yesterday"
                case let d?: when = "\(d) days ago"
                default: when = "recently"
                }
                lines.append("- \(name): \(Formatting.decimal(volume.setsPerWeek, places: 1)) sets per week, last trained \(when)")
            } else {
                lines.append("- \(name): not trained")
            }
        }
        let neglected = volumes.filter { $0.setsPerWeek == 0 && $0.system != .cardio }
        if !neglected.isEmpty {
            lines.append("Least trained and worth prioritizing: "
                         + neglected.map { $0.system.label.capitalized }.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Category activity (what training data cannot see)

    @ViewBuilder
    private var categoryActivityCard: some View {
        // Only the categories a workout cannot represent. Activity is already covered above by
        // real sessions, so repeating it as an entry count would be noise.
        let categories = calc.availableCategories(range: .month).filter { $0 != .activity }
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader("WHAT ELSE YOU HAVE BEEN LOGGING", subtitle: "Last 30 days")
                ForEach(categories) { category in
                    categoryRow(category)
                }
            }
            .healthCard()
        }
    }

    private func categoryRow(_ category: InsightCategory) -> some View {
        let count = calc.totalCount(category, range: .month)
        let streak = calc.currentStreak(category)
        return HStack(spacing: 12) {
            CategoryIcon(category: category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.label).categoryLabel(color: .appTextEmphasis)
                Text("\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 8)
            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(category.accent)
                    Text("\(streak)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.label), \(count) entries in 30 days\(streak > 0 ? ", \(streak) day streak" : "")")
    }

    // MARK: - Recent sessions

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(healthData.workouts.prefix(4))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HealthSectionHeader(titled: "RECENT SESSIONS") {
                    Button("See all") { path.append(HealthRoute.activityFeed) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appAccentSecondary)
                }
                ForEach(recent) { workout in
                    Button { path.append(HealthRoute.workout(workout.id)) } label: {
                        WorkoutRow(
                            workout: workout,
                            load: healthData.analysis?.load(for: workout.id),
                            metric: units.isMetricDistance,
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Trends link

    private var trendsLink: some View {
        NavigationLink {
            TrendsView()
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.appAccentSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.appAccentSecondary.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOURNAL TRENDS")
                        .blackCaps(.subheadline, tracking: 0.6, color: .appTextEmphasis)
                    Text("What you have been writing, over time")
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
            .healthCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HealthEmptyState(
            symbol: "heart.text.square",
            title: "Bring it all together",
            message: "Connect Apple Health and Hevy, or import a Garmin FIT file, and everything you log lands in one history with one set of trends.",
            actionTitle: "Connect a source",
            action: { showConnections = true }
        )
        .padding(.top, 40)
    }
}
