//
//  SettingsView.swift
//  LYFESTYL
//
//  Top left of the camera. The iCloud account that owns the data, daily goals,
//  Apple Health, the on-device model's status, and your data.
//

import CloudKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GoalStore.self) private var goalStore
    @Environment(HealthService.self) private var health
    @Environment(FoodAnalyzer.self) private var analyzer

    @Query(sort: \MealEntry.loggedAt) private var meals: [MealEntry]

    @State private var iCloud: CKAccountStatus?
    @State private var healthDenied = false
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var goalStore = goalStore
        @Bindable var health = health

        NavigationStack {
            Form {
                accountSection
                goalsSection(goals: $goalStore.goals)
                if health.isAvailable { healthSection(enabled: $health.isWritingEnabled) }
                aiSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavHeaderTitle("Account") }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { await refreshAccount() }
            .confirmationDialog("Delete every meal?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All Meals", role: .destructive) {
                    MealLog(context: context, health: health).deleteAll()
                }
            } message: {
                Text("This removes \(meals.count == 1 ? "1 meal" : "\(meals.count) meals") from iCloud on all your devices, and from Apple Health. It can't be undone.")
            }
        }
        .presentationBackground(.appBackground)
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                IconChip(
                    symbol: iCloud == .available ? "icloud.fill" : "icloud.slash.fill",
                    tint: iCloud == .available ? .appAccentSecondary : .appWarning
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Text(accountDetail)
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("ICLOUD").sectionHeader()
        }
    }

    private var accountTitle: String {
        switch iCloud {
        case .available:              "Syncing with iCloud"
        case .noAccount:              "Not signed in to iCloud"
        case .restricted:             "iCloud is restricted"
        case .temporarilyUnavailable: "iCloud is unavailable"
        case nil:                     "Checking iCloud…"
        default:                      "iCloud status unknown"
        }
    }

    private var accountDetail: String {
        switch iCloud {
        case .available:
            "Your meals and goals are private to your iCloud account and stay in step across your devices."
        case .noAccount, .restricted, .temporarilyUnavailable:
            "Meals are saved on this iPhone and will sync once iCloud is available. Sign in from the Settings app."
        default:
            "Your meals are saved on this iPhone."
        }
    }

    private func goalsSection(goals: Binding<Goals>) -> some View {
        Section {
            ForEach(Macro.allCases) { macro in
                Stepper(value: goals[dynamicMember: \.[macro]].clamped(to: Goals.range(for: macro)), in: Goals.range(for: macro), step: Goals.step(for: macro)) {
                    HStack(spacing: 10) {
                        Image(systemName: macro.symbol)
                            .foregroundStyle(macro.accent)
                            .frame(width: 24)
                        Text(macro.name)
                        Spacer(minLength: 4)
                        Text(Formatting.value(goals.wrappedValue[macro], for: macro))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                    }
                }
            }
            NavigationLink {
                GoalCalculatorView()
            } label: {
                Label("Calculate My Goals", systemImage: "function")
            }
        } header: {
            Text("DAILY GOALS").sectionHeader()
        } footer: {
            let g = goals.wrappedValue
            let fromMacros = g.protein * 4 + g.carbs * 4 + g.fat * 9
            Text("Your macro goals add up to about \(Formatting.calories(fromMacros)) kcal.")
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
                Label("Save Meals to Health", systemImage: "heart.fill")
            }
        } header: {
            Text("APPLE HEALTH").sectionHeader()
        } footer: {
            if healthDenied {
                Text("Health access is off. Turn it on in Settings, Health, Data Access & Devices, LYFESTYLE.")
            } else {
                Text("Adds each meal's calories, protein, carbs and fat to Apple Health. Edits and deletes carry over.")
            }
        }
    }

    private var aiSection: some View {
        Section {
            HStack(spacing: 12) {
                IconChip(symbol: "apple.intelligence", tint: analyzer.status.canReadPhotos ? .appAccent : .appWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(aiTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Text(aiDetail)
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("ON-DEVICE AI").sectionHeader()
        } footer: {
            Text("Estimates trade some accuracy for speed. Portions are judged by eye, so check anything that matters to you.")
        }
    }

    private var aiTitle: String {
        switch analyzer.status {
        case .ready:       "Ready"
        case .textOnly:    "Typed foods only"
        case .unavailable: "Unavailable"
        }
    }

    private var aiDetail: String {
        switch analyzer.status {
        case .ready:
            "Photos are read by Apple's on-device model. They never leave this iPhone and are never saved."
        case .textOnly:
            "This iPhone's model can't read photos, but it can estimate foods you type."
        case .unavailable(let message):
            message
        }
    }

    private var dataSection: some View {
        Section {
            ShareLink(
                item: MealExport(rows: meals.map { ($0.loggedAt, $0.items) }),
                preview: SharePreview("LYFESTYL Meals.csv")
            ) {
                Label("Export Meals as CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(meals.isEmpty)

            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Delete All Meals", systemImage: "trash")
            }
            .disabled(meals.isEmpty)
        } header: {
            Text("YOUR DATA").sectionHeader()
        } footer: {
            Text("\(meals.count == 1 ? "1 meal" : "\(meals.count) meals") logged. No photos are stored, only foods and numbers.")
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(spacing: 10) {
                LyfestylLogo(size: 28)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.footnote)
                    .foregroundStyle(.appTextMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func refreshAccount() async {
        iCloud = try? await CKContainer(identifier: LYFESTYLEApp.cloudContainerID).accountStatus()
    }
}

private extension Binding where Value == Double {
    /// Keeps a Stepper usable if a synced goal arrives outside the range.
    func clamped(to range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { Swift.min(Swift.max(wrappedValue, range.lowerBound), range.upperBound) },
            set: { wrappedValue = $0 }
        )
    }
}
