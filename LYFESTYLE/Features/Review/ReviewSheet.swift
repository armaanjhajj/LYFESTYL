//
//  ReviewSheet.swift
//  LYFESTYL
//
//  The drawer that rises after a snap. X on the left dismisses (and drops the
//  photo), + on the right logs. Every food can be opened, edited, swapped
//  through search, or removed. The time is recorded silently. The same sheet
//  edits meals from the history, with a checkmark in place of the +.
//

import SwiftUI

enum SearchPurpose: Hashable {
    /// The sheet opened on search (low confidence, no food, or no photo).
    case start
    case add
    case replace(UUID)
}

enum ReviewRoute: Hashable {
    case edit(UUID)
    case search(SearchPurpose)
    case manual(name: String, purpose: SearchPurpose)
}

struct ReviewSheet: View {
    @Bindable var draft: MealDraft
    let onLog: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Environment(FoodAnalyzer.self) private var analyzer
    @State private var path: [ReviewRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close, action: onDismiss)
                            .accessibilityLabel(draft.editing == nil ? "Discard" : "Close")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) { trailingActions }
                }
                .navigationDestination(for: ReviewRoute.self, destination: destination)
        }
        .tint(.appAccent)
    }

    // MARK: - Root by phase

    @ViewBuilder
    private var root: some View {
        switch draft.phase {
        case .analyzing:
            AnalyzingView(foods: draft.streaming)
        case .review:
            DraftReviewList(draft: draft, path: $path, onDelete: onDelete)
        case .search(let message):
            FoodSearchView(
                purpose: .start,
                message: message,
                suggestions: draft.suggestions,
                onPick: { pick($0, for: .start) }
            )
        case .failed(let message):
            FailedView(
                message: message,
                canRetry: draft.canRetry,
                onRetry: { draft.analyze(with: analyzer) },
                onSearch: { draft.phase = .search(nil) }
            )
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        if draft.canRetry, draft.phase != .analyzing {
            Button("Retry", systemImage: "arrow.clockwise") {
                path.removeAll()
                draft.analyze(with: analyzer)
            }
        }
        if draft.phase == .review {
            if draft.editing == nil {
                Button("Log", systemImage: "plus", action: onLog)
                    .buttonStyle(.glassProminent)
                    .disabled(draft.items.isEmpty)
            } else {
                Button("Save", systemImage: "checkmark", role: .confirm, action: onLog)
                    .disabled(draft.items.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: ReviewRoute) -> some View {
        switch route {
        case .edit(let id):
            ItemEditorView(draft: draft, itemID: id, path: $path)
        case .search(let purpose):
            FoodSearchView(
                purpose: purpose,
                message: nil,
                suggestions: [],
                alternatives: alternatives(for: purpose),
                onPick: { pick($0, for: purpose) }
            )
        case .manual(let name, let purpose):
            ManualFoodView(name: name) { pick([$0], for: purpose) }
        }
    }

    private func alternatives(for purpose: SearchPurpose) -> [String] {
        guard case .replace(let id) = purpose, let index = draft.index(of: id) else { return [] }
        return draft.items[index].alternatives
    }

    /// Whatever search returned, put it in the meal and go back to the list.
    private func pick(_ foods: [FoodItem], for purpose: SearchPurpose) {
        switch purpose {
        case .start, .add:      draft.add(foods)
        case .replace(let id):  draft.replace(id, with: foods)
        }
        path.removeAll()
    }
}

// MARK: - Analyzing

private struct AnalyzingView: View {
    let foods: [StreamedFood]

    private var total: Nutrition {
        foods.map {
            Nutrition(calories: $0.calories ?? 0, protein: $0.protein ?? 0, carbs: $0.carbs ?? 0, fat: $0.fat ?? 0)
        }.total
    }

    var body: some View {
        // The same layout as the review list, so the result lands in place.
        List {
            Section {
                NutritionSummary(nutrition: total)
                    .shimmering(foods.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
            Section {
                ForEach(foods) { food in
                    StreamingRow(food: food)
                }
                // One more placeholder: there may be more on the plate.
                SkeletonRow(delay: foods.isEmpty ? 0 : 0.15)
                if foods.isEmpty {
                    SkeletonRow(delay: 0.1)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(.compact)
        .scrollDisabled(true)
        .sensoryFeedback(.impact(weight: .light), trigger: foods.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(foods.isEmpty ? "Reading the photo" : "Found \(foods.map(\.name).joined(separator: ", "))")
    }
}

/// A food that has been named but may still be getting its numbers.
private struct StreamingRow: View {
    let food: StreamedFood

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(food.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                if let portion = food.portion {
                    Text(portion)
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                        .transition(.blurReplace)
                } else {
                    SkeletonBar(width: 64, height: 10)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                if let calories = food.calories {
                    Text("\(Formatting.calories(calories)) kcal")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                        .contentTransition(.numericText(value: calories))
                } else {
                    SkeletonBar(width: 70, height: 14)
                }
                if food.hasNumbers {
                    MacroLine(protein: food.protein ?? 0, carbs: food.carbs ?? 0, fat: food.fat ?? 0)
                        .transition(.blurReplace)
                } else {
                    SkeletonBar(width: 90, height: 9)
                }
            }
            .monospacedDigit()
        }
        .animation(.snappy, value: food)
        .shimmering(!food.hasNumbers)
        .arrives()
    }
}

/// Where a food is about to land.
private struct SkeletonRow: View {
    var delay: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 130, height: 14)
                SkeletonBar(width: 70, height: 10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                SkeletonBar(width: 70, height: 14)
                SkeletonBar(width: 90, height: 9)
            }
        }
        .padding(.vertical, 4)
        .shimmering()
        .arrives(delay: delay)
    }
}

// MARK: - Review list

private struct DraftReviewList: View {
    @Bindable var draft: MealDraft
    @Binding var path: [ReviewRoute]
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                NutritionSummary(nutrition: draft.nutrition)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            Section {
                ForEach(draft.items) { item in
                    NavigationLink(value: ReviewRoute.edit(item.id)) {
                        DraftItemRow(item: item)
                    }
                }
                .onDelete { offsets in
                    draft.items.remove(atOffsets: offsets)
                }
                Button {
                    path.append(.search(.add))
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
            }

            if draft.editing != nil {
                Section {
                    Button("Delete Meal", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(.compact)
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Meal", role: .destructive, action: onDelete)
        }
    }
}

struct DraftItemRow: View {
    let item: DraftItem

    var body: some View {
        FoodRow(food: item.food) {
            if item.needsCheck {
                Text("CHECK")
                    .font(.caption2)
                    .fontWeight(.black)
                    .tracking(0.6)
                    .foregroundStyle(.appWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appWarning.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Name and portion on the left, calories and macros on the right.
struct FoodRow<Badge: View>: View {
    let food: FoodItem
    @ViewBuilder var badge: Badge

    init(food: FoodItem, @ViewBuilder badge: () -> Badge = { EmptyView() }) {
        self.food = food
        self.badge = badge()
    }

    var body: some View {
        let n = food.nutrition
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(food.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    badge
                }
                Text(food.portionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Formatting.calories(n.calories)) kcal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                MacroLine(protein: n.protein, carbs: n.carbs, fat: n.fat)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The top of the drawer: big calories with how much of the day they are,
/// and a ring per macro filling toward the daily goal.
struct NutritionSummary: View {
    let nutrition: Nutrition
    @Environment(GoalStore.self) private var goalStore

    var body: some View {
        let goals = goalStore.goals
        let dayShare = goals.calories > 0 ? nutrition.calories / goals.calories : 0
        VStack(spacing: 20) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Formatting.calories(nutrition.calories))
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(.appTextEmphasis)
                        .contentTransition(.numericText(value: nutrition.calories))
                    Text("CALORIES").sectionHeader(color: .appTextMuted)
                }
                Spacer()
                Text("\(Formatting.percent(fraction: dayShare)) OF DAY")
                    .font(.caption.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.appTextMuted)
                    .contentTransition(.numericText(value: dayShare))
            }
            HStack(spacing: 0) {
                ForEach([Macro.protein, .carbs, .fat]) { macro in
                    VStack(spacing: 8) {
                        ZStack {
                            ProgressRing(fraction: goals[macro] > 0 ? nutrition[macro] / goals[macro] : 0, tint: macro.accent, lineWidth: 9)
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text(Formatting.grams(nutrition[macro], includeUnit: false))
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(.appTextEmphasis)
                                    .contentTransition(.numericText(value: nutrition[macro]))
                                Text("g")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.appTextMuted)
                            }
                        }
                        .frame(width: 78, height: 78)
                        Text(macro.label)
                            .font(.caption.weight(.black))
                            .tracking(0.5)
                            .foregroundStyle(macro.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .animation(.snappy, value: nutrition)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Formatting.calories(nutrition.calories)) calories, \(Formatting.grams(nutrition.protein)) protein, \(Formatting.grams(nutrition.carbs)) carbs, \(Formatting.grams(nutrition.fat)) fat")
    }
}

// MARK: - Failure

private struct FailedView: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            EmptyStateView(
                symbol: "exclamationmark.triangle.fill",
                title: "Couldn't read that",
                message: message,
                tint: .appWarning
            )
            HStack(spacing: 12) {
                if canRetry {
                    Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.glassProminent)
                }
                Button("Search", systemImage: "magnifyingglass", action: onSearch)
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
    }
}
