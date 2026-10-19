//
//  ItemEditorView.swift
//  LYFESTYL
//
//  Edit one food: fix the name, scale the servings, correct the numbers (type
//  or slide), swap it for another guess or a search result, or remove it with
//  the trash button.
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .capsNavigationTitle(item.food.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        draft.remove(itemID)
                        path.removeAll()
                    }
                    .tint(.appDestructive)
                }
            }
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
/// Every number can be typed (tap its value) or dragged (its slider).
struct FoodFields: View {
    @Binding var food: FoodItem
    @FocusState private var focused: Macro?

    var body: some View {
        Section {
            HStack {
                TextField("Name", text: $food.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Image(systemName: "pencil")
                    .foregroundStyle(.appTextMuted)
                    .accessibilityHidden(true)
            }
            TextField("Portion, like 1 cup", text: $food.portion)
                .foregroundStyle(.appText)
            Stepper(value: $food.servings, in: 0.25...20, step: 0.25) {
                HStack {
                    Text("Servings")
                    Spacer()
                    Text(Formatting.servings(food.servings))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                }
            }
        }

        Section {
            ForEach(Macro.allCases) { macro in
                NutrientEditor(macro: macro, value: binding(for: macro), focused: $focused)
            }
        } header: {
            Text(food.servings == 1 ? "NUTRITION" : "PER SERVING").sectionHeader()
        } footer: {
            if food.servings != 1 {
                let n = food.nutrition
                Text("Total \(Formatting.calories(n.calories)) cal · \(Formatting.macroLine(protein: n.protein, carbs: n.carbs, fat: n.fat))")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
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

/// One number: its value in a tinted pill you can tap to type, and a slider
/// in the macro's color underneath.
private struct NutrientEditor: View {
    let macro: Macro
    @Binding var value: Double
    var focused: FocusState<Macro?>.Binding

    /// Fixed while editing so the slider doesn't rescale under your thumb.
    @State private var upper: Double = 100

    private var step: Double { macro == .calories ? 5 : 1 }
    private var isFocused: Bool { focused.wrappedValue == macro }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: macro.symbol)
                    .foregroundStyle(macro.accent)
                    .frame(width: 24)
                Text(macro.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                        .frame(minWidth: 36)
                        .fixedSize()
                        .focused(focused, equals: macro)
                    Text(macro.unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appTextMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(macro.accent.opacity(isFocused ? 0.22 : 0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(macro.accent.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5))
                .contentShape(Capsule())
                .onTapGesture { focused.wrappedValue = macro }
                .animation(.snappy, value: isFocused)
            }
            Slider(
                value: Binding(get: { min(value, upper) }, set: { value = ($0 / step).rounded() * step }),
                in: 0...upper
            )
            .tint(macro.accent)
            .accessibilityLabel(macro.name)
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: Int(value / (step * 5)))
        .onAppear { upper = Self.upperBound(macro, value) }
        .onChange(of: value) { _, new in
            if new > upper { upper = Self.upperBound(macro, new) }
        }
    }

    private static func upperBound(_ macro: Macro, _ value: Double) -> Double {
        let floor: Double = switch macro {
        case .calories: 1000
        case .protein:  100
        case .carbs:    150
        case .fat:      80
        }
        let round: Double = macro == .calories ? 100 : 10
        return max(floor, (value * 2 / round).rounded(.up) * round)
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
