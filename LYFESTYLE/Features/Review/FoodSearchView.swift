//
//  FoodSearchView.swift
//  LYFESTYL
//
//  Pick a food. Reached when the model isn't sure (its guesses come first),
//  from any item in the drawer, from Add Food, and from the camera's search
//  button. Sources, in order: the model's suggestions, foods you've logged
//  before (exact numbers you already accepted), a bundled table of common
//  foods, an on-device estimate of whatever you typed, and manual entry.
//

import SwiftData
import SwiftUI

struct FoodSearchView: View {
    let purpose: SearchPurpose
    let message: String?
    let suggestions: [DraftItem]
    var alternatives: [String] = []
    let onPick: ([FoodItem]) -> Void

    @Environment(FoodAnalyzer.self) private var analyzer
    @Query(Self.recentDescriptor) private var recentMeals: [MealEntry]

    @State private var query = ""
    @State private var estimating: String?
    @State private var estimateError: String?

    private static var recentDescriptor: FetchDescriptor<MealEntry> {
        var descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        descriptor.fetchLimit = 80
        return descriptor
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if trimmed.isEmpty {
                idleSections
            } else {
                resultSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .capsNavigationTitle(purpose == .start ? "Find Food" : "Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or describe a food")
        .onSubmit(of: .search) {
            if analyzer.status.canEstimateText, !trimmed.isEmpty { estimate(trimmed) }
        }
        .onChange(of: query) { estimateError = nil }
    }

    // MARK: - Before typing

    @ViewBuilder
    private var idleSections: some View {
        if let message {
            Section {
                Label {
                    Text(message).foregroundStyle(.appText)
                } icon: {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.appWarning)
                }
            }
        }

        if !suggestions.isEmpty || !alternatives.isEmpty {
            Section {
                ForEach(suggestions) { suggestion in
                    Button { onPick([suggestion.food]) } label: { FoodRow(food: suggestion.food) }
                    ForEach(suggestion.alternatives, id: \.self) { name in
                        estimateRow(name, portion: suggestion.food.portion)
                    }
                }
                ForEach(alternatives, id: \.self) { name in
                    estimateRow(name, portion: nil)
                }
            } header: {
                Text("SUGGESTIONS").sectionHeader()
            }
        }

        if recentFoods.isEmpty {
            if suggestions.isEmpty && alternatives.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "Search for a food",
                        message: analyzer.status.canEstimateText
                            ? "Type a food, or describe a whole meal like \"two eggs and toast\"."
                            : "Type a food to find it, or enter it by hand."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            Section {
                ForEach(recentFoods.prefix(15)) { food in
                    Button { onPick([food]) } label: { FoodRow(food: food) }
                }
            } header: {
                Text("RECENT").sectionHeader()
            }
        }
    }

    // MARK: - While typing

    @ViewBuilder
    private var resultSections: some View {
        Section {
            if analyzer.status.canEstimateText {
                Button { estimate(trimmed) } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Estimate \u{201C}\(trimmed)\u{201D}").foregroundStyle(.appTextEmphasis)
                                Text("Calories and macros, worked out on this iPhone")
                                    .font(.caption)
                                    .foregroundStyle(.appTextMuted)
                            }
                        } icon: {
                            Image(systemName: "wand.and.sparkles").foregroundStyle(.appAccent)
                        }
                        Spacer()
                        if estimating == trimmed { ProgressView() }
                    }
                }
                .disabled(estimating != nil)
            }
            NavigationLink(value: ReviewRoute.manual(name: trimmed, purpose: purpose)) {
                Label {
                    Text("Enter \u{201C}\(trimmed)\u{201D} by Hand").foregroundStyle(.appTextEmphasis)
                } icon: {
                    Image(systemName: "keyboard").foregroundStyle(.appAccentSecondary)
                }
            }
        } footer: {
            if let estimateError { Text(estimateError) }
        }

        let mine = matches(in: recentFoods)
        if !mine.isEmpty {
            Section {
                ForEach(mine) { food in
                    Button { onPick([food]) } label: { FoodRow(food: food) }
                }
            } header: {
                Text("YOUR FOODS").sectionHeader()
            }
        }

        let common = CommonFoods.search(trimmed)
        if !common.isEmpty {
            Section {
                ForEach(common) { food in
                    Button { onPick([food]) } label: { FoodRow(food: food) }
                }
            } header: {
                Text("COMMON FOODS").sectionHeader()
            }
        }
    }

    // MARK: - Pieces

    /// A model guess with no numbers yet. Tapping estimates it, then picks it.
    private func estimateRow(_ name: String, portion: String?) -> some View {
        Button {
            estimate(portion.map { "\(name), \($0)" } ?? name, label: name)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Text("Tap to estimate")
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                }
                Spacer()
                if estimating == name { ProgressView() }
            }
        }
        .disabled(estimating != nil || !analyzer.status.canEstimateText)
    }

    private func estimate(_ text: String, label: String? = nil) {
        let key = label ?? text
        estimating = key
        estimateError = nil
        Task {
            defer { estimating = nil }
            do {
                let items = try await analyzer.estimate(text)
                if items.isEmpty {
                    estimateError = "Couldn't estimate that. Try different words, or enter it by hand."
                } else {
                    onPick(items.map(\.food))
                }
            } catch {
                estimateError = FoodAnalyzer.message(for: error)
            }
        }
    }

    /// Every distinct food from recent meals, most recent first, with the
    /// numbers the person last logged it with.
    private var recentFoods: [FoodItem] {
        var seen = Set<String>()
        var foods: [FoodItem] = []
        for meal in recentMeals {
            for food in meal.items {
                let key = food.name.lowercased()
                guard seen.insert(key).inserted else { continue }
                var copy = food
                copy.id = UUID()
                foods.append(copy)
            }
        }
        return foods
    }

    private func matches(in foods: [FoodItem]) -> [FoodItem] {
        let words = trimmed.lowercased().split(separator: " ")
        return foods.filter { food in
            let name = food.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }
        .prefix(8)
        .map { $0 }
    }
}
