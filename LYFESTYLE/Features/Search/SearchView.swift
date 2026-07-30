//
//  SearchView.swift
//  LYFESTYL
//
//  The surface behind the tab bar's dedicated search button (CLAUDE.md §2.1:
//  native `.searchable`, never a hand-rolled field, the magnifying glass, the
//  glass capsule, the cancel button and the scroll behavior all come for free).
//  Mirrors Apple Health's Search screen: a large title, a browse-by-category list
//  while idle, and live entry results as you type. Reuses the Log's row + detail
//  so an entry looks identical wherever it appears.
//

import SwiftUI

struct SearchView: View {
    @Environment(JournalStore.self) private var store
    @State private var search = ""
    @State private var path = NavigationPath()

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var results: [JournalEntry] {
        guard !query.isEmpty else { return [] }
        return store.entries.filter { matches($0, query) }
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
            .searchable(text: $search, prompt: "Search your log")
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
            ForEach(results) { entry in
                NavigationLink(value: entry.id) {
                    EntryRowView(entry: entry)
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("\(results.count) \(results.count == 1 ? "Result" : "Results")")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
        }
    }

    private func count(for category: InsightCategory) -> Int {
        store.entries.filter { $0.category == category }.count
    }

    private func matches(_ entry: JournalEntry, _ query: String) -> Bool {
        entry.rawText.lowercased().contains(query)
            || (entry.title?.lowercased().contains(query) ?? false)
            || (entry.subtag?.lowercased().contains(query) ?? false)
            || (entry.category?.label.lowercased().contains(query) ?? false)
            || entry.fields.contains { $0.value.lowercased().contains(query) }
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
    let category: InsightCategory

    private var entries: [JournalEntry] {
        store.entries
            .filter { $0.category == category }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    symbol: category.symbolName,
                    title: "No \(category.label) yet",
                    message: "Entries filed under \(category.label.lowercased()) will show up here."
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.id) {
                            EntryRowView(entry: entry)
                        }
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
}
