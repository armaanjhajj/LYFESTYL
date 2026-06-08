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

                Section("About") {
                    infoRow("Entries", "\(store.entries.count)")
                    infoRow("Breakdown schema", "v\(InsightSchema.version)")
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
                ToolbarItem(placement: .principal) { LyfestylLogo(size: 20) }
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

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.appText)
            Spacer()
            Text(value).foregroundStyle(.appTextMuted).monospacedDigit()
        }
        .listRowBackground(Color.appSurface)
    }
}
