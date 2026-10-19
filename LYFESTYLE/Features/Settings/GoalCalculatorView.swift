//
//  GoalCalculatorView.swift
//  LYFESTYL
//
//  Suggests daily goals from height, weight, age, sex, activity and aim, using
//  the Mifflin-St Jeor equation. Apple Health can fill in the body numbers.
//  Shown from Settings and during onboarding.
//

import SwiftUI

/// The calculator's form sections, shared by Settings and onboarding.
struct GoalCalculatorForm: View {
    @Binding var profile: BodyProfile

    @Environment(HealthService.self) private var health
    @State private var filling = false

    private let usesImperial = Locale.current.measurementSystem == .us

    var body: some View {
        Section {
            Picker("Sex", selection: $profile.sex) {
                Text("Female").tag(BodyProfile.Sex.female)
                Text("Male").tag(BodyProfile.Sex.male)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            Stepper(value: $profile.age, in: 14...100) {
                LabeledContent("Age", value: "\(profile.age)")
            }

            if usesImperial {
                LabeledContent("Height") {
                    HStack(spacing: 0) {
                        Picker("Feet", selection: feet) {
                            ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                        }
                        Picker("Inches", selection: inches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                        }
                    }
                    .labelsHidden()
                }
                NumberField(title: "Weight", value: pounds, unit: "lb")
            } else {
                NumberField(title: "Height", value: $profile.heightCm, unit: "cm")
                NumberField(title: "Weight", value: $profile.weightKg, unit: "kg")
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
        } header: {
            Text("ABOUT YOU").sectionHeader()
        }

        Section {
            Picker("Activity", selection: $profile.activity) {
                ForEach(BodyProfile.Activity.allCases, id: \.self) { activity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.label)
                        Text(activity.detail)
                            .font(.caption)
                            .foregroundStyle(.appTextMuted)
                    }
                    .tag(activity)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("ACTIVITY").sectionHeader()
        }

        Section {
            Picker("Goal", selection: $profile.aim) {
                ForEach(BodyProfile.Aim.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
        } header: {
            Text("GOAL").sectionHeader()
        }

        Section {
            let goals = profile.suggestedGoals
            ForEach(Macro.allCases) { macro in
                LabeledContent {
                    Text(Formatting.value(goals[macro], for: macro))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                } label: {
                    Label {
                        Text(macro.name)
                    } icon: {
                        Image(systemName: macro.symbol).foregroundStyle(macro.accent)
                    }
                }
            }
        } header: {
            Text("SUGGESTED DAILY GOALS").sectionHeader()
        } footer: {
            Text("A starting point, not medical advice.")
        }
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

private struct NumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(unit).foregroundStyle(.appTextMuted)
            }
        }
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
        .capsNavigationTitle("Calculate Goals")
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
