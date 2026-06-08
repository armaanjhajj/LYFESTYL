//
//  LogView.swift
//  LYFESTYL
//
//  The history surface (CLAUDE.md §1): a clean, Apple-Health-style list of
//  entries grouped by day, with native search, pull-to-refresh, swipe-to-delete,
//  and an entry point into Trends. All chrome is native (NavigationStack +
//  .searchable + .toolbar get Liquid Glass automatically).
//

import SwiftUI

enum LogRoute: Hashable {
    case trends
}

struct LogView: View {
    @Environment(JournalStore.self) private var store
    @State private var search = ""
    @State private var showProfile = false
    @State private var path = NavigationPath()

    private var filteredDays: [(day: Date, entries: [JournalEntry])] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let groups = store.entriesByDay
        guard !trimmed.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.entries.filter { entry in
                entry.rawText.lowercased().contains(trimmed)
                    || (entry.overallSummary?.lowercased().contains(trimmed) ?? false)
                    || entry.insights.contains { $0.title.lowercased().contains(trimmed) || $0.detail.lowercased().contains(trimmed) }
            }
            return matches.isEmpty ? nil : (group.day, matches)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !store.hasAnyEntries {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { EntryDetailView(entryID: $0) }
            .navigationDestination(for: LogRoute.self) { route in
                switch route {
                case .trends: TrendsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { LyfestylLogo(size: 22) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .task {
                #if DEBUG
                if path.isEmpty {
                    if ProcessInfo.processInfo.environment["LYFE_TRENDS"] == "1" {
                        path.append(LogRoute.trends)
                    } else if ProcessInfo.processInfo.environment["LYFE_DETAIL"] == "1",
                              let first = store.entries.first {
                        path.append(first.id)
                    }
                }
                #endif
            }
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink(value: LogRoute.trends) {
                    TrendsSummaryCard(insightCount: store.allInsights.count,
                                      entryCount: store.entries.count)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(filteredDays, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: entry.id) {
                            EntryRowView(entry: entry)
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.deleteEntry(entry) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(dayLabel(group.day))
                        .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                }
            }

            if filteredDays.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "Search entries")
        .refreshable { await store.refresh() }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "square.and.pencil",
            title: "No entries yet",
            message: "Head to Journal and dump your first thought. Your structured history shows up here."
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()
    }
}

// MARK: - Trends summary card

struct TrendsSummaryCard: View {
    let insightCount: Int
    let entryCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.appAccent)
                .frame(width: 44, height: 44)
                .background(Color.appAccent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("TRENDS")
                    .blackCaps(.subheadline, tracking: 0.8, color: .appTextEmphasis)
                Text("Nutrition, activity, sleep & health over time")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14)
    }
}
