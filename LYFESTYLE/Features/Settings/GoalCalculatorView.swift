//
//  GoalCalculatorView.swift
//  LYFESTYL
//
//  Suggests daily goals from height, weight, age, sex, activity and aim, using
//  the Mifflin-St Jeor equation. Apple Health can fill in the body numbers.
//

import SwiftUI

/// The calculator's form sections.
struct GoalCalculatorForm: View {
    @Binding var profile: BodyProfile

    @Environment(HealthService.self) private var health
    @State private var filling = false
    @FocusState private var focused: BodyField?

    private enum BodyField: Hashable { case age, height, weight }

    private let usesImperial = Locale.current.measurementSystem == .us

    var body: some View {
        Section {
            Picker("Sex", selection: $profile.sex) {
                Text("Female").tag(BodyProfile.Sex.female)
                Text("Male").tag(BodyProfile.Sex.male)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            SliderField(title: "Age", value: age, range: 14...90, unit: "yr", focus: $focused, id: .age)

            if usesImperial {
                HStack {
                    Text("Height")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Spacer()
                    Picker("Feet", selection: feet) {
                        ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                    }
                    Picker("Inches", selection: inches) {
                        ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                    }
                }
                .labelsHidden()
                SliderField(title: "Weight", value: pounds, range: 80...400, unit: "lb", focus: $focused, id: .weight)
            } else {
                SliderField(title: "Height", value: $profile.heightCm, range: 130...215, unit: "cm", focus: $focused, id: .height)
                SliderField(title: "Weight", value: $profile.weightKg, range: 35...180, unit: "kg", focus: $focused, id: .weight)
            }

            if health.isAvailable {
                Button {
                    filling = true
                    Task {
                        profile = await health.fillProfile(profile)
                        filling = false
                    }
                } label: {
                    HStack {
                        Label("Fill from Apple Health", systemImage: "heart.fill")
                        Spacer()
                        if filling { ProgressView() }
                    }
                }
                .disabled(filling)
            }
        }

        Section {
            Picker("Activity", selection: $profile.activity) {
                ForEach(BodyProfile.Activity.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Goal", selection: $profile.aim) {
                ForEach(BodyProfile.Aim.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
        }

        Section {
            let goals = profile.suggestedGoals
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(Formatting.calories(goals.calories))
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.appTextEmphasis)
                        .contentTransition(.numericText(value: goals.calories))
                    Text("CAL A DAY").sectionHeader(color: .appTextMuted)
                }
                MacroLine(protein: goals.protein, carbs: goals.carbs, fat: goals.fat)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .animation(.snappy, value: goals)
        } footer: {
            Text("A starting point, not medical advice.")
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    private var age: Binding<Double> {
        Binding(get: { Double(profile.age) }, set: { profile.age = Int($0.rounded()) })
    }

    // MARK: - Imperial bindings over canonical units

    private var totalInches: Int { Int((profile.heightCm / 2.54).rounded()) }

    private var feet: Binding<Int> {
        Binding(
            get: { totalInches / 12 },
            set: { profile.heightCm = Double($0 * 12 + totalInches % 12) * 2.54 }
        )
    }

    private var inches: Binding<Int> {
        Binding(
            get: { totalInches % 12 },
            set: { profile.heightCm = Double((totalInches / 12) * 12 + $0) * 2.54 }
        )
    }

    private var pounds: Binding<Double> {
        Binding(
            get: { (profile.weightKg * 2.20462).rounded() },
            set: { profile.weightKg = $0 / 2.20462 }
        )
    }
}

/// The calculator as a Settings screen.
struct GoalCalculatorView: View {
    @Environment(GoalStore.self) private var goalStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile = BodyProfile()

    var body: some View {
        Form {
            GoalCalculatorForm(profile: $profile)
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .capsNavigationTitle("Your Goals")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use", systemImage: "checkmark", role: .confirm) {
                    goalStore.profile = profile
                    goalStore.goals = profile.suggestedGoals
                    dismiss()
                }
            }
        }
        .onAppear { if let saved = goalStore.profile { profile = saved } }
    }
}
