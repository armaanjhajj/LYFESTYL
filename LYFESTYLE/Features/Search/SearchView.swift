//
//  SearchView.swift
//  LYFESTYL
//
//  The surface behind the tab bar's dedicated search button (CLAUDE.md §2.1:
//  native `.searchable`, never a hand-rolled field, the magnifying glass, the
//  glass capsule, the cancel button and the scroll behavior all come for free).
//  Mirrors Apple Health's Search screen: a large title, a browse-by-category list while idle,
//  and live results as you type. Searches the WHOLE history, so a Hevy session, a run off a
//  watch and a written note are all findable in one place, and by exercise name too. Reuses the
//  same rows as everywhere else, so a session looks identical wherever it appears.
//

import SwiftUI

struct SearchView: View {
    @Environment(JournalStore.self) private var store
    @Environment(HealthDataStore.self) private var healthData
    @Environment(UnitPreference.self) private var units
    @State private var search = ""
    @State private var path = NavigationPath()

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Everything the app knows, filtered. Workouts match on their title, sport, source and
    /// the names of the exercises in them, which is usually how someone looks for a session.
    private var results: [TimelineItem] {
        guard !query.isEmpty else { return [] }
        return TimelineItem.build(entries: store.entries, workouts: healthData.workouts)
            .filter { $0.searchText.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    categoriesSection
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                } else {
                    resultsSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Search")
            .navigationDestination(for: UUID.self) { EntryDetailView(entryID: $0) }
            .navigationDestination(for: InsightCategory.self) { CategoryEntriesView(category: $0) }
            .navigationDestination(for: HealthRoute.self) { route in
                if case .workout(let id) = route { WorkoutDetailView(workoutID: id) }
            }
            .searchable(text: $search, prompt: "Search sessions and entries")
        }
    }

    // MARK: - Idle: browse by category (Apple Health "Health Categories")

    private var categoriesSection: some View {
        Section {
            ForEach(InsightCategory.allCases.sorted { $0.sortIndex < $1.sortIndex }) { category in
                NavigationLink(value: category) {
                    CategoryBrowseRow(category: category, count: count(for: category))
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Lifestyle Categories")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
        }
    }

    // MARK: - Typing: matching entries

    private var resultsSection: some View {
        Section {
            ForEach(results) { item in
                resultRow(item)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text("\(results.count) \(results.count == 1 ? "Result" : "Results")")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
        }
    }

    @ViewBuilder
    private func resultRow(_ item: TimelineItem) -> some View {
        switch item {
        case .entry(let entry):
            NavigationLink(value: entry.id) { EntryRowView(entry: entry) }
        case .workout(let workout):
            NavigationLink(value: HealthRoute.workout(workout.id)) {
                WorkoutRow(
                    workout: workout,
                    load: healthData.analysis?.load(for: workout.id),
                    metric: units.isMetricDistance
                )
            }
        }
    }

    /// How many things are filed under a category, counting sessions as ACTIVITY.
    private func count(for category: InsightCategory) -> Int {
        let entries = store.entries.filter { $0.category == category && $0.promotedWorkoutID == nil }.count
        return category == .activity ? entries + healthData.workouts.count : entries
    }
}

// MARK: - Category browse row

private struct CategoryBrowseRow: View {
    let category: InsightCategory
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: category, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .categoryLabel(color: .appTextEmphasis)
                Text(count == 0 ? "No entries yet"
                                : "\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 12)
    }
}

// MARK: - Category drill-down

struct CategoryEntriesView: View {
    @Environment(JournalStore.self) private var store
    @Environment(HealthDataStore.self) private var healthData
    @Environment(UnitPreference.self) private var units
    let category: InsightCategory

    /// Everything filed under this category. ACTIVITY includes real sessions from every source,
    /// not just written notes, so drilling in shows the training rather than a thin subset.
    private var items: [TimelineItem] {
        TimelineItem.build(
            entries: store.entries,
            workouts: category == .activity ? healthData.workouts : []
        )
        .filter { $0.category == category }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    symbol: category.symbolName,
                    title: "No \(category.label) yet",
                    message: "Entries filed under \(category.label.lowercased()) will show up here."
                )
            } else {
                List {
                    ForEach(items) { item in
                        row(item)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle(category.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ item: TimelineItem) -> some View {
        switch item {
        case .entry(let entry):
            NavigationLink(value: entry.id) { EntryRowView(entry: entry) }
        case .workout(let workout):
            NavigationLink(value: HealthRoute.workout(workout.id)) {
                WorkoutRow(
                    workout: workout,
                    load: healthData.analysis?.load(for: workout.id),
                    metric: units.isMetricDistance
                )
            }
        }
    }
}
