//
//  JournalView.swift
//  LYFESTYL
//
//  The LYFE surface: the full, atomic history of every journal entry plus the
//  create flow. Tap the top-right button to compose, it morphs from a plus into
//  a checkmark and the tab bar slides away for a clean, full-screen editor (which
//  is why the keyboard never shifts the surrounding layout). Save with the
//  checkmark or the back button; the new entry lands in the list and analyzes
//  itself on device. Entries are atomic and timestamped, no day grouping.
//
//  All chrome is native (NavigationStack + .toolbar get Liquid Glass for free,
//  §2). Search lives in its own tab-bar button (SearchView); trends live in STYL.
//

import SwiftUI

struct JournalView: View {
    @Environment(JournalStore.self) private var store
    @Environment(InsightEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isEditing = false
    @State private var showPicker = false
    @State private var draft = ""
    @State private var usedVoice = false
    @State private var commitTrigger = 0
    @State private var path = NavigationPath()

    private var entries: [JournalEntry] {
        store.entries.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !engine.isAvailable {
                        ModelStatusBanner(availability: engine.availability)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    if store.hasAnyEntries {
                        historyList
                    } else {
                        emptyState
                    }
                }

                if isEditing {
                    EntryComposer(
                        text: $draft,
                        usedVoice: $usedVoice,
                        commitTrigger: $commitTrigger,
                        onCommit: persistAndClose
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isEditing ? .hidden : .automatic, for: .tabBar)
            .toolbar { toolbarContent }
            .navigationDestination(for: UUID.self) { EntryDetailView(entryID: $0) }
            .sensoryFeedback(.success, trigger: store.savedTick)
            .sheet(isPresented: $showPicker) {
                CategoryPickerSheet(source: .text, onFreeWrite: { startComposing() })
            }
        }
        .onAppear { engine.refreshAvailability() }
    }

    // MARK: - Toolbar (logo ⇄ back · plus ⇄ checkmark + menu)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button { requestCommit() } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Save and go back")
            }
        }

        // A single group keeps the morphing primary button's identity stable (so
        // plus ⇄ checkmark actually animates) and the ellipsis fixed to its left.
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isEditing {
                Menu {
                    Button(role: .destructive) { discard() } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Entry options")
            }

            Button {
                if isEditing { requestCommit() } else { showPicker = true }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .tint(.appAccent)
            .accessibilityLabel(isEditing ? "Save entry" : "New entry")
        }
    }

    // MARK: - History

    private var historyList: some View {
        List {
            ForEach(entries) { entry in
                row(for: entry)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.deleteEntry(entry) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private func row(for entry: JournalEntry) -> some View {
        // Processing entries aren't openable yet; everything else drills into detail.
        // We navigate via a plain Button (not NavigationLink) so the row gets the
        // full width with no trailing disclosure chevron.
        if entry.status == .processed || entry.status == .failed {
            Button {
                path.append(entry.id)
            } label: {
                EntryRowView(entry: entry)
            }
            .buttonStyle(.plain)
        } else {
            EntryRowView(entry: entry)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            LyfestylLogo(size: 56)
            VStack(spacing: 8) {
                Text("NO ENTRIES")
                    .blackCaps(.title2, tracking: 1, color: .appTextEmphasis)
                Text("To add an entry, tap the + button.")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func startComposing() {
        draft = ""
        usedVoice = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { isEditing = true }
    }

    /// Ask the composer to save. It finalizes any in-flight recording (draining the
    /// transcript into `draft`) before calling `persistAndClose`.
    private func requestCommit() {
        commitTrigger += 1
    }

    /// Persist the draft (if any) and return to the history. Empty drafts just close.
    /// Invoked by the composer once recording has been finalized.
    private func persistAndClose() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let source: EntrySource = usedVoice ? .voice : .text
            Task { await store.addEntry(text: text, source: source) }
        }
        draft = ""
        usedVoice = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { isEditing = false }
    }

    private func discard() {
        draft = ""
        usedVoice = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { isEditing = false }
    }
}
