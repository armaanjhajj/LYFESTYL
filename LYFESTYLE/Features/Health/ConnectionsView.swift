//
//  ConnectionsView.swift
//  LYFESTYL
//
//  Where the user links their data sources.
//
//  The screen is deliberately honest about what each connection can and cannot do, because
//  the differences are large and invisible otherwise:
//
//    APPLE HEALTH is automatic and covers Apple Watch fully. Garmin also writes here, but only
//    twelve categories, and explicitly no GPS track and no per-workout heart-rate series.
//
//    HEVY needs the user's own API key, which requires a Hevy Pro account. It is the only
//    source with set-by-set lifting detail.
//
//    GARMIN has no usable direct API for an app like this (the developer programme is closed
//    to new applicants and requires a server), so the connection is FIT file import, which
//    needs no account and unlocks everything Apple Health leaves out.
//
//  Saying all of this plainly is better than a "Connect Garmin" button that silently does less
//  than the user expects.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @Environment(HealthDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showHevySheet = false
    @State private var showFITImporter = false
    @State private var importSummary: HealthDataStore.FITImportSummary?
    @State private var showImportResult = false

    var body: some View {
        NavigationStack {
            List {
                appleHealthSection
                hevySection
                garminSection
                if store.hasAnyData { dataSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showHevySheet) { HevyConnectSheet() }
            .fileImporter(
                isPresented: $showFITImporter,
                allowedContentTypes: FITFileTypes.all,
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                Task {
                    let summary = await store.importFITFiles(urls: urls)
                    importSummary = summary
                    showImportResult = true
                }
            }
            .alert("Import complete", isPresented: $showImportResult, presenting: importSummary) { _ in
                Button("OK", role: .cancel) {}
            } message: { summary in
                Text(summary.message + (summary.errors.isEmpty ? "" : "\n\n" + summary.errors.prefix(3).joined(separator: "\n")))
            }
        }
    }

    // MARK: - Apple Health

    private var appleHealthSection: some View {
        Section {
            ConnectionRow(
                source: .appleHealth,
                state: store.connections[.appleHealth] ?? .notConnected,
                subtitle: "Workouts, sleep, heart rate and daily activity"
            )
            if store.connections[.appleHealth]?.isConnected != true {
                Button("Connect Apple Health") {
                    Task { await store.connectAppleHealth() }
                }
                .disabled(!store.isHealthAvailable)
            } else {
                Button("Sync now") {
                    Task { await store.syncAppleHealth() }
                }
                .disabled(store.connections[.appleHealth]?.isBusy == true)
            }
        } header: {
            Text("AUTOMATIC")
        } footer: {
            Text("Reads whatever your iPhone, Apple Watch, or another app has written to Health. If you use the Garmin Connect app, its daily activity and sleep arrive here too, though Garmin sends only a summary of each workout and no GPS or heart-rate detail.")
        }
    }

    // MARK: - Hevy

    private var hevySection: some View {
        Section {
            ConnectionRow(
                source: .hevy,
                state: store.connections[.hevy] ?? .notConnected,
                subtitle: "Set-by-set lifting history"
            )
            if store.connections[.hevy]?.isConnected == true {
                Button("Sync now") {
                    Task { await store.syncHevy() }
                }
                .disabled(store.connections[.hevy]?.isBusy == true)
                Button("Disconnect Hevy", role: .destructive) {
                    Task { await store.disconnectHevy() }
                }
            } else {
                Button("Connect Hevy") { showHevySheet = true }
            }
        } header: {
            Text("HEVY")
        } footer: {
            Text("Brings in every workout with its exercises, sets, reps, weights and RPE. That set-level detail is what makes weekly volume per muscle, estimated one-rep max trends and plateau detection possible. Needs an API key from your Hevy account, which requires Hevy Pro.")
        }
    }

    // MARK: - Garmin

    private var garminSection: some View {
        Section {
            ConnectionRow(
                source: .garmin,
                state: store.connections[.garmin] ?? .notConnected,
                subtitle: "Import .fit files for full session detail"
            )
            Button {
                showFITImporter = true
            } label: {
                Label("Import FIT files", systemImage: "square.and.arrow.down")
            }
            Button {
                if let url = URL(string: "https://connect.garmin.com/modern/") {
                    openURL(url)
                }
            } label: {
                Label("Open Garmin Connect", systemImage: "safari")
            }
        } header: {
            Text("GARMIN")
        } footer: {
            Text("""
            Garmin has no public API an app like this can use without running a server, so detail comes from the original .fit files instead. That is actually the richer path: a .fit file carries the full GPS track, second-by-second heart rate, power, cadence, running dynamics, sleep stages, Body Battery and stress, none of which Garmin sends to Apple Health.

            To get one session: open the activity in Garmin Connect on the web, use the gear menu, and choose Export Original.

            To get everything at once: request your account data export from Garmin, then import the .fit files from the archive.
            """)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent("Sessions", value: "\(store.workouts.count)")
            LabeledContent("Days of wellness", value: "\(store.snapshots.count)")
            if let analysis = store.analysis {
                LabeledContent("Insights", value: "\(analysis.insights.count)")
                if let duration = store.lastAnalysisDuration {
                    LabeledContent(
                        "Last analysis",
                        value: "\(Formatting.decimal(duration * 1000, places: 0)) ms"
                    )
                }
            }
            if !store.dismissedInsightIDs.isEmpty {
                Button("Restore \(store.dismissedInsightIDs.count) dismissed insight\(store.dismissedInsightIDs.count == 1 ? "" : "s")") {
                    store.restoreDismissedInsights()
                }
            }
            Button("Remove all synced data", role: .destructive) {
                Task { await store.disconnectAll() }
            }
        } header: {
            Text("YOUR DATA")
        } footer: {
            Text("Everything stays on your device and in your own private iCloud. Nothing is sent anywhere else.")
        }
    }
}

// MARK: - FIT file types

/// The document types the importer accepts.
///
/// `.fit` has no registered system UTI, so it is declared here by filename extension. Without
/// this the file picker would grey out every FIT file the user is trying to select.
enum FITFileTypes {
    static let fit = UTType(filenameExtension: "fit") ?? .data

    static var all: [UTType] {
        // `.data` is included so a file exported with an unexpected extension is still
        // selectable; the decoder validates the magic bytes regardless.
        [fit, .data]
    }
}

// MARK: - Hevy connect sheet

/// Collects the user's Hevy API key, with the steps to find it.
struct HevyConnectSheet: View {
    @Environment(HealthDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorText: String?
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A secure field: the key is a bearer credential for the whole account.
                    SecureField("Paste your API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($keyFieldFocused)
                        .submitLabel(.go)
                        .onSubmit { connect() }
                } header: {
                    Text("API KEY")
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(Solar.red)
                    } else {
                        Text("The key is stored in your device keychain and never leaves this device except to talk to Hevy.")
                    }
                }

                Section {
                    stepRow(1, "Open hevy.com in a browser and sign in.")
                    stepRow(2, "Go to Settings, then Developer.")
                    stepRow(3, "Generate an API key and copy it.")
                    Button {
                        if let url = URL(string: "https://hevy.com/settings?developer") {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Hevy developer settings", systemImage: "safari")
                    }
                } header: {
                    Text("WHERE TO FIND IT")
                } footer: {
                    Text("The developer page is only on the Hevy website, not in the phone app, and it requires a Hevy Pro subscription.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Connect Hevy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Connect") { connect() }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { keyFieldFocused = true }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Solar.violet)
                .frame(width: 20, height: 20)
                .background(Solar.violet.opacity(0.16), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.appText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isConnecting else { return }
        isConnecting = true
        errorText = nil
        Task {
            let success = await store.connectHevy(apiKey: key)
            isConnecting = false
            if success {
                dismiss()
            } else {
                errorText = store.connections[.hevy]?.errorText
                    ?? "That key was not accepted. Check it and try again."
            }
        }
    }
}
