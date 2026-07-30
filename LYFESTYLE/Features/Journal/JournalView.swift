//
//  JournalView.swift
//  LYFESTYL
//
//  The LYFE surface: ONE history of everything you have recorded, plus the create flow.
//
//  Journal entries and workouts share this list, in time order, whatever they came from: a
//  thought you wrote, a meal, a Hevy lifting session, a run off a watch, a workout you built
//  here. The user never has to think about which app a session came from to find it.
//
//  Grouped by day, because a mixed list of sessions and notes is far easier to read with day
//  headers than as a flat run of timestamps.
//
//  All chrome is native (NavigationStack + .toolbar get Liquid Glass for free, §2). Search
//  lives in its own tab-bar button; the analysis lives in STYL.
//

import SwiftUI

struct JournalView: View {
    @Environment(JournalStore.self) private var store
    @Environment(HealthDataStore.self) private var healthData
    @Environment(InsightEngine.self) private var engine
    @Environment(UnitPreference.self) private var units
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isEditing = false
    @State private var showPicker = false
    @State private var draft = ""
    @State private var usedVoice = false
    @State private var commitTrigger = 0
    @State private var path = NavigationPath()

    /// The one history: entries and workouts from every source, newest first.
    private var timeline: [TimelineItem] {
        TimelineItem.build(entries: store.entries, workouts: healthData.workouts)
    }

    private var days: [(day: Date, items: [TimelineItem])] {
        TimelineItem.groupedByDay(timeline)
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
                    if !timeline.isEmpty {
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
            .navigationDestination(for: HealthRoute.self) { route in
                if case .workout(let id) = route { WorkoutDetailView(workoutID: id) }
            }
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
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in
                        row(for: item)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                if item.isDeletable {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text(Formatting.relativeDay(group.day).uppercased())
                        .font(.caption)
                        .fontWeight(.black)
                        .tracking(0.8)
                        .foregroundStyle(.appTextMuted)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refresh()
            await healthData.refreshAll()
        }
    }

    @ViewBuilder
    private func row(for item: TimelineItem) -> some View {
        switch item {
        case .entry(let entry):
            // Entries still being organized are not openable yet.
            if entry.status == .processed || entry.status == .failed {
                Button { path.append(entry.id) } label: { EntryRowView(entry: entry) }
                    .buttonStyle(.plain)
            } else {
                EntryRowView(entry: entry)
            }
        case .workout(let workout):
            Button { path.append(HealthRoute.workout(workout.id)) } label: {
                WorkoutRow(
                    workout: workout,
                    load: healthData.analysis?.load(for: workout.id),
                    metric: units.isMetricDistance
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func delete(_ item: TimelineItem) {
        Task {
            switch item {
            case .entry(let entry):     await store.deleteEntry(entry)
            case .workout(let workout): await healthData.deleteManualWorkout(workout)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            LyfestylLogo(size: 56)
            VStack(spacing: 8) {
                Text("NOTHING YET")
                    .blackCaps(.title2, tracking: 1, color: .appTextEmphasis)
                Text("Tap + to log something, or connect Apple Health and Hevy in STYL to bring your training in.")
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
