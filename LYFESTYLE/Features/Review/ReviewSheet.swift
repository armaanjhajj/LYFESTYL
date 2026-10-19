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
            AnalyzingView(found: draft.found)
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
    let found: [String]

    var body: some View {
        VStack(spacing: 20) {
            ProcessingIndicator()
            if !found.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(found, id: \.self) { name in
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.appTextEmphasis)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.appSurface, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: found)
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
        .accessibilityElement(children: .combine)
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
                Text(Formatting.macroLine(protein: n.protein, carbs: n.carbs, fat: n.fat))
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Big calories plus the three macros, the top of the drawer.
struct NutritionSummary: View {
    let nutrition: Nutrition

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatting.calories(nutrition.calories))
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.appTextEmphasis)
                    .contentTransition(.numericText())
                Text("CALORIES").sectionHeader(color: .appTextMuted)
            }
            Spacer()
            HStack(spacing: 16) {
                ForEach([Macro.protein, .carbs, .fat]) { macro in
                    VStack(spacing: 2) {
                        Text(Formatting.grams(nutrition[macro]))
                            .font(.headline)
                            .foregroundStyle(macro.accent)
                            .contentTransition(.numericText())
                        Text(macro.label)
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundStyle(.appTextMuted)
                    }
                }
            }
        }
        .monospacedDigit()
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
