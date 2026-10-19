//
//  OnboardingView.swift
//  LYFESTYL
//
//  First launch only. What the app does and what it keeps, then goals. A
//  second device that already has goals in iCloud skips straight to the camera.
//

import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(GoalStore.self) private var goalStore
    @State private var showGoals = false
    @State private var profile = BodyProfile()

    var body: some View {
        NavigationStack {
            welcome
                .navigationDestination(isPresented: $showGoals) { goals }
        }
        .tint(.appAccent)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            LyfestylLogo(size: 64)
                .padding(.bottom, 20)
            Text("Snap your food. That's the whole app.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appText)
                .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 24) {
                Feature(
                    symbol: "camera.viewfinder",
                    tint: .appAccent,
                    title: "Point and snap",
                    detail: "Every food on the plate, itemized with calories and macros in a few seconds. Fix anything with a tap."
                )
                Feature(
                    symbol: "lock.shield.fill",
                    tint: .appAccentSecondary,
                    title: "Photos are never kept",
                    detail: "Read on this iPhone by Apple's on-device model, then thrown away. Only the numbers stay."
                )
                Feature(
                    symbol: "icloud.fill",
                    tint: Macro.fat.accent,
                    title: "Free, no sign up",
                    detail: "Meals sync privately through your own iCloud account and can go to Apple Health."
                )
            }
            Spacer()
            Spacer()

            Button {
                if goalStore.hasStoredGoals { onDone() } else { showGoals = true }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
    }

    private var goals: some View {
        Form {
            Section {
                Text("Set your daily goals")
                    .blackCaps(.title2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            GoalCalculatorForm(profile: $profile)
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { onDone() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Use", systemImage: "checkmark", role: .confirm) {
                    goalStore.profile = profile
                    goalStore.goals = profile.suggestedGoals
                    onDone()
                }
            }
        }
    }
}

private struct Feature: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconChip(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.appTextEmphasis)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
