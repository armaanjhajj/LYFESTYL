//
//  StylView.swift
//  LYFESTYL
//
//  The STYL surface: "what you've been logging." A calm, neutral activity read,
//  category counts, current streaks, and recent entries, plus the measured
//  HealthKit lane where it's available. No standings, no scores, no judgment, the
//  app reflects your activity, it doesn't grade it.
//
//  The full Swift Charts history (TrendsView) and the account sheet (ProfileView)
//  live one tap away so STYL stays a status surface, not a dashboard dump.
//
//  Honesty rule (CLAUDE.md): the only figures shown are measured (HealthKit), in
//  their own clearly-attributed lane.
//

import SwiftUI

struct StylView: View {
    @Environment(JournalStore.self) private var store
    @Environment(HealthService.self) private var health
    @State private var showAccount = false
    @State private var showSuggestion = false
    @State private var path = NavigationPath()

    private var calc: TrendCalculator { TrendCalculator(entries: store.entries) }
    private var muscleBalance: MuscleBalance { MuscleBalance(entries: store.entries) }
    private var hasAnySignal: Bool { store.hasAnyEntries || !health.summary.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if hasAnySignal {
                    VStack(spacing: 22) {
                        overviewCard
                        categoryActivityCard
                        if muscleBalance.hasData {
                            MuscleBalanceCard(entries: store.entries)
                        }
                        SuggestSessionButton { showSuggestion = true }
                        healthArea
                        recentSection
                        trendsLink
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 20) {
                        connectHealthCard
                        emptyState
                    }
                    .padding(20)
                }
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { EntryDetailView(entryID: $0) }
            .refreshable {
                await store.refresh()
                await health.refresh()
            }
            .task { await health.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .sheet(isPresented: $showAccount) { ProfileView() }
            .sheet(isPresented: $showSuggestion) {
                AIChatView(
                    contextSummary: muscleBalance.summaryForModel(),
                    initialPrompt: "Suggest a balanced session for me based on what I have trained recently."
                )
            }
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        let thisWeek = calc.totalEntries(range: .week)
        let total = calc.totalEntries(range: .quarter)
        let categories = calc.availableCategories(range: .quarter).count
        return HStack(spacing: 0) {
            stat(value: "\(thisWeek)", label: "THIS WEEK")
            divider
            stat(value: "\(total)", label: "LAST 90 DAYS")
            divider
            stat(value: "\(categories)", label: "CATEGORIES")
        }
        .cardSurface()
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.appTextEmphasis)
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.appTextMuted.opacity(0.2))
            .frame(width: 1, height: 36)
    }

    // MARK: - Category activity

    @ViewBuilder
    private var categoryActivityCard: some View {
        let categories = calc.availableCategories(range: .month)
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHAT YOU'VE BEEN LOGGING")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                ForEach(categories) { category in
                    categoryRow(category)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func categoryRow(_ category: InsightCategory) -> some View {
        let count = calc.totalCount(category, range: .month)
        let streak = calc.currentStreak(category)
        return HStack(spacing: 12) {
            CategoryIcon(category: category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .categoryLabel(color: .appTextEmphasis)
                Text("\(count) \(count == 1 ? "entry" : "entries") · 30 days")
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

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(store.entries.sorted { $0.createdAt > $1.createdAt }.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                ForEach(recent) { entry in
                    if entry.status == .processed || entry.status == .failed {
                        Button { path.append(entry.id) } label: {
                            EntryRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                    } else {
                        EntryRowView(entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Health (measured lane / connect affordance)

    @ViewBuilder
    private var healthArea: some View {
        if !health.summary.isEmpty {
            measuredSection
        } else if health.isHealthAvailable, !health.hasRequestedAuthorization {
            connectHealthCard
        }
    }

    private var measuredSection: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEASURED")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").font(.caption2)
                    Text("Apple Health").font(.caption)
                }
                .foregroundStyle(.appTextMuted)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(health.summary.metrics) { MeasuredMetricTile(metric: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private var connectHealthCard: some View {
        if health.isHealthAvailable, !health.hasRequestedAuthorization {
            Button {
                Task { await health.requestAuthorization() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Solar.magenta)
                        .frame(width: 36, height: 36)
                        .background(Solar.magenta.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONNECT APPLE HEALTH")
                            .blackCaps(.subheadline, tracking: 0.6, color: .appTextEmphasis)
                        Text("Add measured activity, heart, and sleep alongside your log.")
                            .font(.caption)
                            .foregroundStyle(.appTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appTextMuted)
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
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
                    Text("TRENDS OVER TIME")
                        .blackCaps(.subheadline, tracking: 0.6, color: .appTextEmphasis)
                    Text("Your category activity over time")
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            symbol: "heart.text.square",
            title: "Nothing logged yet",
            message: "Log a few entries in LYFE and your activity and trends build here."
        )
        .padding(.top, 70)
    }
}
