//
//  SettingsView.swift
//  LYFESTYL
//
//  Top left of the camera. Your profile (photo and name), daily goals, Apple
//  Health, and your data. The on-device model only shows up here when
//  something is wrong with it.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GoalStore.self) private var goalStore
    @Environment(HealthService.self) private var health
    @Environment(FoodAnalyzer.self) private var analyzer
    @Environment(ProfileStore.self) private var profile

    @Query(sort: \MealEntry.loggedAt) private var meals: [MealEntry]

    @State private var healthDenied = false
    @State private var confirmDeleteAll = false
    @FocusState private var focused: Macro?
    @FocusState private var editingName: Bool

    var body: some View {
        @Bindable var goalStore = goalStore
        @Bindable var health = health
        @Bindable var profile = profile

        NavigationStack {
            Form {
                profileSection(name: $profile.name)
                goalsSection(goals: $goalStore.goals)
                if health.isAvailable { healthSection(enabled: $health.isWritingEnabled) }
                if !analyzer.status.canReadPhotos { aiSection }
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavHeaderTitle("Account") }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil; editingName = false }
                }
            }
            .confirmationDialog("Delete every meal?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All Meals", role: .destructive) {
                    MealLog(context: context, health: health).deleteAll()
                }
            } message: {
                Text("Removes them from iCloud and Apple Health. This can't be undone.")
            }
        }
        .presentationBackground(.appBackground)
    }

    // MARK: - Sections

    /// Photo and name.
    private func profileSection(name: Binding<String>) -> some View {
        Section {
            VStack(spacing: 12) {
                ProfilePhotoButton()

                TextField("Your Name", text: name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.appTextEmphasis)
                    .multilineTextAlignment(.center)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($editingName)

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func goalsSection(goals: Binding<Goals>) -> some View {
        Section {
            ForEach(Macro.allCases) { macro in
                SliderField(
                    title: macro.name,
                    symbol: macro.symbol,
                    tint: macro.accent,
                    value: goals[dynamicMember: \.[macro]],
                    range: Goals.range(for: macro),
                    step: Goals.step(for: macro),
                    unit: macro.unit,
                    focus: $focused,
                    id: macro
                )
            }
            NavigationLink {
                GoalCalculatorView()
            } label: {
                Label("Calculate for Me", systemImage: "function")
            }
        } header: {
            Text("DAILY GOALS").sectionHeader()
        }
    }

    private func healthSection(enabled: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { enabled.wrappedValue },
                set: { on in
                    if on {
                        Task {
                            let granted = await health.requestAccess()
                            enabled.wrappedValue = granted
                            healthDenied = !granted
                        }
                    } else {
                        enabled.wrappedValue = false
                    }
                }
            )) {
                Label("Save to Apple Health", systemImage: "heart.fill")
            }
        } footer: {
            if healthDenied {
                Text("Allow access in the Health app.")
            }
        }
    }

    private var aiSection: some View {
        Section {
            HStack(spacing: 12) {
                IconChip(symbol: "apple.intelligence", tint: .appWarning)
                Text(aiMessage)
                    .font(.subheadline)
                    .foregroundStyle(.appText)
            }
        }
    }

    private var aiMessage: String {
        switch analyzer.status {
        case .ready:                    ""
        case .textOnly:                 "Photos can't be read on this iPhone. Search still works."
        case .unavailable(let message): message
        }
    }

    private var dataSection: some View {
        Section {
            ShareLink(
                item: MealExport(rows: meals.map { ($0.loggedAt, $0.items) }),
                preview: SharePreview("LYFESTYL Meals.csv")
            ) {
                Label("Export Meals", systemImage: "square.and.arrow.up")
            }
            .disabled(meals.isEmpty)

            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Delete All Meals", systemImage: "trash")
                    .foregroundStyle(meals.isEmpty ? Color.appTextMuted : Color.appDestructive)
            }
            .disabled(meals.isEmpty)
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous)
                            .strokeBorder(Color.appTextMuted.opacity(0.2), lineWidth: 0.5)
                    )
                    .accessibilityLabel("LYFESTYL")
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    .font(.footnote)
                    .foregroundStyle(.appTextMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

}
