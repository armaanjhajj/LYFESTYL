//
//  ProfileView.swift
//  LYFESTYL
//
//  Account + status sheet: who you're signed in as, the on-device model's state,
//  a privacy note, and sign-out. Native List/Form chrome.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(InsightEngine.self) private var engine
    @Environment(JournalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.appAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(auth.displayName ?? "Your account")
                                .font(.headline)
                                .foregroundStyle(.appTextEmphasis)
                            Text("Signed in with Apple")
                                .font(.caption)
                                .foregroundStyle(.appTextMuted)
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                Section("On-device AI") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: engine.availability.symbolName)
                            .foregroundStyle(engine.isAvailable ? Solar.green : Solar.yellow)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(engine.availability.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                            Text(engine.availability.message)
                                .font(.caption)
                                .foregroundStyle(.appTextMuted)
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                Section("Apple Health") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Solar.magenta)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(healthTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                            Text(healthMessage)
                                .font(.caption)
                                .foregroundStyle(.appTextMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if health.isHealthAvailable, !health.hasRequestedAuthorization {
                            Button("Connect") { Task { await health.requestAuthorization() } }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                                .tint(.appAccent)
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                Section("About") {
                    infoRow("Entries", "\(store.entries.count)")
                    infoRow("Schema", "v\(InsightSchema.version)")
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill").foregroundStyle(Solar.violet)
                        Text("Your entries are analyzed entirely on your device. Only your structured history syncs to your private account.")
                            .font(.caption)
                            .foregroundStyle(.appTextMuted)
                    }
                    .listRowBackground(Color.appSurface)
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { LyfestylLogo(size: 20, style: .mono) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        await store.reset()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your data stays safe in your account and on this device's cache.")
            }
        }
    }

    private var healthTitle: String {
        if !health.isHealthAvailable { return "Not available on this device" }
        return health.hasRequestedAuthorization ? "Connected" : "Not connected"
    }

    private var healthMessage: String {
        if !health.isHealthAvailable {
            return "This device doesn't provide Apple Health data."
        }
        if health.hasRequestedAuthorization {
            return "Measured activity, heart, and sleep appear on STYL when available. Manage access in the Health app under Sharing."
        }
        return "Connect to add measured data to your STYL status and check-ins. Read on-device only."
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.appText)
            Spacer()
            Text(value).foregroundStyle(.appTextMuted).monospacedDigit()
        }
        .listRowBackground(Color.appSurface)
    }
}
