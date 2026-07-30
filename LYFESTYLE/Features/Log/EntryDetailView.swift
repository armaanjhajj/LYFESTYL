//
//  EntryDetailView.swift
//  LYFESTYL
//
//  The structured breakdown of one entry, Apple-Health-clean: the raw text, the
//  model's summary, and a card per category with estimates + rank. Resolves the
//  entry live from the store so status changes (processing → done) reflect here.
//

import SwiftUI

struct EntryDetailView: View {
    let entryID: UUID
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var entry: JournalEntry? {
        store.entries.first { $0.id == entryID }
    }

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else {
                EmptyStateView(
                    symbol: "doc.questionmark",
                    title: "Entry not found",
                    message: "This entry may have been deleted."
                )
            }
        }
        .background(Color.appBackground)
        .navigationTitle(entry.map { $0.createdAt.formatted(.dateTime.month().day()) } ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if entry.status != .processing, entry.category == nil {
                            Button {
                                Task { await store.process(entryID: entry.id) }
                            } label: {
                                Label("Re-file", systemImage: "arrow.clockwise")
                            }
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Entry", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry {
                    Task { await store.deleteEntry(entry) }
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the entry from all your devices.")
        }
    }

    private func content(_ entry: JournalEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metaHeader(entry)

                if entry.status == .processing || entry.status == .pending {
                    processingBanner
                } else if entry.status == .failed {
                    failedBanner(entry)
                }

                if let category = entry.category {
                    categoryCard(category, subtag: entry.subtag)
                }

                if let workout = entry.workout, !workout.exercises.isEmpty {
                    workoutSection(workout)
                }

                if !entry.rawText.isEmpty {
                    noteCard(entry)
                }

                if !entry.fields.isEmpty {
                    organizedSection(entry)
                }
            }
            .padding(20)
        }
    }

    private func categoryCard(_ category: InsightCategory, subtag: String?) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.label)
                    .categoryLabel(color: .appTextEmphasis)
                if let subtag, !subtag.isEmpty {
                    Text(subtag.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .cardSurface()
    }

    private func organizedSection(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORGANIZED")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            VStack(spacing: 12) {
                ForEach(entry.fields) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(field.label.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(0.4)
                            .foregroundStyle(.appTextMuted)
                        Spacer(minLength: 8)
                        Text(field.value)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.appTextEmphasis)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func workoutSection(_ workout: WorkoutPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WORKOUT")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                Text(workout.countSummary)
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }

            VStack(spacing: 12) {
                ForEach(workout.exercises) { logged in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(logged.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                            if let ex = logged.exercise {
                                Text(ex.muscleSummary)
                                    .font(.caption)
                                    .foregroundStyle(.appTextMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(logged.summary(unit: workout.unit))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if !workout.systemsWorked.isEmpty {
                    Divider().overlay(Color.appTextMuted.opacity(0.2))
                    FlowLayout(spacing: 8) {
                        ForEach(workout.systemsWorked) { system in
                            systemChip(system)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .cardSurface()
        }
    }

    private func systemChip(_ system: BodySystem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(system.accent)
            Text(system.label)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.4)
                .foregroundStyle(.appTextEmphasis)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(system.accent.opacity(0.16), in: Capsule())
    }

    private func metaHeader(_ entry: JournalEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.source.symbolName)
                .font(.caption)
                .foregroundStyle(.appTextMuted)
            Text(entry.createdAt.formatted(.dateTime.weekday(.wide).hour().minute()))
                .font(.subheadline)
                .foregroundStyle(.appTextMuted)
            Spacer()
        }
    }

    private func noteCard(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU WROTE")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            Text(entry.rawText)
                .font(.body.weight(.medium))
                .foregroundStyle(.appTextEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface()
    }

    private var processingBanner: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.appAccent)
            Text("Analyzing on device…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.appTextEmphasis)
            Spacer()
        }
        .cardSurface(padding: 14)
    }

    private func failedBanner(_ entry: JournalEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Solar.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis didn't finish")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text("Your entry is saved. Tap to try again.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer()
            Button("Retry") { Task { await store.process(entryID: entry.id) } }
                .buttonStyle(.bordered)
                .tint(.appAccent)
        }
        .cardSurface(padding: 14)
    }
}
