//
//  JournalView.swift
//  LYFESTYL
//
//  The capture surface (CLAUDE.md §1). Open → type immediately, or tap the glass
//  voice button and talk. Zero friction, multiple entries per day, auto-stamped
//  to today. The Log/Voice controls live on a Liquid Glass action bar (chrome).
//

import SwiftUI

struct JournalView: View {
    @Environment(JournalStore.self) private var store
    @Environment(InsightEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var recentEntryID: UUID?
    @State private var showRecorder = false
    @FocusState private var composerFocused: Bool

    private var recentEntry: JournalEntry? {
        guard let id = recentEntryID else { return nil }
        return store.entries.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !engine.isAvailable {
                        ModelStatusBanner(availability: engine.availability)
                    }

                    composer

                    if let entry = recentEntry {
                        RecentlyLoggedView(entry: entry)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                EntryDetailView(entryID: id)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LyfestylLogo(size: 22)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .sheet(isPresented: $showRecorder) {
                VoiceRecorderView { transcript in
                    appendTranscript(transcript)
                }
            }
            .sensoryFeedback(.success, trigger: recentEntryID)
        }
        .onAppear {
            engine.refreshAvailability()
            // Auto-focus so the user can type the instant the app opens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                composerFocused = true
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY")
                .blackCaps(.largeTitle, tracking: 1, color: .appTextEmphasis)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.appTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "What happened today?",
                text: $text,
                prompt: Text("What happened today? Eat, move, sleep, feel — just dump it.")
                    .foregroundColor(.appTextMuted),
                axis: .vertical
            )
            .font(.title3)
            .foregroundStyle(.appTextEmphasis)
            .tint(.appAccent)
            .focused($composerFocused)
            .lineLimit(4...14)
            .submitLabel(.return)
        }
        .cardSurface(padding: 18)
        .animation(reduceMotion ? nil : .smooth, value: text.isEmpty)
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    composerFocused = false
                    showRecorder = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.glass)
                .tint(.appAccent)
                .disabled(!SpeechService.isSupported)
                .accessibilityLabel("Record a voice entry")

                Button(action: log) {
                    Label("Log Entry", systemImage: "arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(.appAccent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

    private func log() {
        let entryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entryText.isEmpty else { return }
        text = ""
        Task {
            let id = await store.addEntry(text: entryText, source: .text)
            withAnimation(reduceMotion ? nil : .smooth) { recentEntryID = id }
        }
        // Keep focus so logging several things in a row stays frictionless.
        composerFocused = true
    }

    private func appendTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if text.isEmpty {
            text = clean
        } else {
            text += (text.hasSuffix(" ") ? "" : " ") + clean
        }
        composerFocused = true
    }
}
