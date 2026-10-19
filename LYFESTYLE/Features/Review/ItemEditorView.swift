//
//  ItemEditorView.swift
//  LYFESTYL
//
//  Edit one food: fix the name, scale the servings, correct the numbers, or
//  swap it for one of the model's other guesses or a search result.
//

import SwiftUI

struct ItemEditorView: View {
    @Bindable var draft: MealDraft
    let itemID: UUID
    @Binding var path: [ReviewRoute]

    @Environment(FoodAnalyzer.self) private var analyzer
    @State private var swapping: String?
    @State private var swapError: String?

    var body: some View {
        if let index = draft.index(of: itemID) {
            let item = draft.items[index]
            Form {
                if item.needsCheck || !item.alternatives.isEmpty {
                    alternativesSection(item)
                }
                FoodFields(food: $draft.items[index].food)
                Section {
                    NavigationLink(value: ReviewRoute.search(.replace(itemID))) {
                        Label("Find a Different Food", systemImage: "magnifyingglass")
                    }
                    Button("Remove from Meal", systemImage: "trash", role: .destructive) {
                        draft.remove(itemID)
                        path.removeAll()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .capsNavigationTitle(item.food.name)
            .onDisappear { draft.markChecked(itemID) }
        } else {
            // Removed or replaced while this screen was on the stack.
            Color.appBackground
        }
    }

    @ViewBuilder
    private func alternativesSection(_ item: DraftItem) -> some View {
        Section {
            ForEach(item.alternatives, id: \.self) { name in
                Button {
                    swap(to: name, portion: item.food.portion)
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.appTextEmphasis)
                        Spacer()
                        if swapping == name { ProgressView() }
                    }
                }
                .disabled(swapping != nil)
            }
        } header: {
            Text(item.needsCheck ? "NOT SURE? IT COULD BE" : "IT COULD ALSO BE").sectionHeader()
        } footer: {
            if let swapError { Text(swapError) }
        }
    }

    /// Re-estimate as one of the model's other guesses, keeping the portion.
    private func swap(to name: String, portion: String) {
        swapping = name
        swapError = nil
        Task {
            defer { swapping = nil }
            if analyzer.status.canEstimateText,
               let food = try? await analyzer.estimate(portion.isEmpty ? name : "\(name), \(portion)").first?.food {
                draft.replace(itemID, with: [food])
                path.removeAll()
            } else if let food = CommonFoods.search(name, limit: 1).first {
                draft.replace(itemID, with: [food])
                path.removeAll()
            } else {
                swapError = "Couldn't estimate \(name). Try searching for it instead."
            }
        }
    }
}

/// The editable fields of a food, shared by the item editor and manual entry.
struct FoodFields: View {
    @Binding var food: FoodItem

    var body: some View {
        Section {
            TextField("Name", text: $food.name)
                .font(.body.weight(.semibold))
            TextField("Portion, like 1 cup or 2 slices", text: $food.portion)
        } header: {
            Text("FOOD").sectionHeader()
        }

        Section {
            Stepper(value: $food.servings, in: 0.25...20, step: 0.25) {
                LabeledContent("Servings", value: Formatting.servings(food.servings))
            }
        }

        Section {
            ForEach(Macro.allCases) { macro in
                NumberRow(macro: macro, value: binding(for: macro))
            }
        } header: {
            Text(food.servings == 1 ? "NUTRITION" : "NUTRITION PER SERVING").sectionHeader()
        } footer: {
            if food.servings != 1 {
                let n = food.nutrition
                Text("\(Formatting.servings(food.servings)) total: \(Formatting.calories(n.calories)) kcal, \(Formatting.macroLine(protein: n.protein, carbs: n.carbs, fat: n.fat))")
            } else {
                Text("Estimates. Adjust anything that looks off.")
            }
        }
    }

    private func binding(for macro: Macro) -> Binding<Double> {
        Binding(
            get: { food.base[macro] },
            set: { value in
                let value = max(0, value)
                switch macro {
                case .calories: food.base.calories = value
                case .protein:  food.base.protein = value
                case .carbs:    food.base.carbs = value
                case .fat:      food.base.fat = value
                }
            }
        )
    }
}

private struct NumberRow: View {
    let macro: Macro
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(macro.unit)
                    .foregroundStyle(.appTextMuted)
            }
        } label: {
            Label {
                Text(macro.name)
            } icon: {
                Image(systemName: macro.symbol).foregroundStyle(macro.accent)
            }
        }
    }
}

/// A food typed in by hand.
struct ManualFoodView: View {
    let onAdd: (FoodItem) -> Void
    @State private var food: FoodItem

    init(name: String, onAdd: @escaping (FoodItem) -> Void) {
        self.onAdd = onAdd
        _food = State(initialValue: FoodItem(name: name, portion: "", base: .zero))
    }

    var body: some View {
        Form {
            FoodFields(food: $food)
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .capsNavigationTitle("New Food")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", systemImage: "checkmark", role: .confirm) { onAdd(food) }
                    .disabled(food.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
