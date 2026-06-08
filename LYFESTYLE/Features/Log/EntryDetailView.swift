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
                        if entry.status != .processing {
                            Button {
                                Task { await store.process(entryID: entry.id) }
                            } label: {
                                Label("Re-analyze", systemImage: "arrow.clockwise")
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
            Text("This removes the entry and its breakdown from all your devices.")
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

                rawCard(entry)

                if entry.status == .processed {
                    if entry.insights.isEmpty {
                        noDetails
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BREAKDOWN")
                                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                            ForEach(entry.sortedInsights) { insight in
                                InsightCard(insight: insight)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
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

    private func rawCard(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU WROTE")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            Text(entry.rawText)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = entry.overallSummary, !summary.isEmpty, summary != entry.rawText {
                Divider().overlay(Color.appTextMuted.opacity(0.3))
                Text(summary)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private var noDetails: some View {
        Text("No trackable details found in this entry.")
            .font(.subheadline)
            .foregroundStyle(.appTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}
