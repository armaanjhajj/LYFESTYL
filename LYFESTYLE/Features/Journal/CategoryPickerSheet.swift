//
//  CategoryPickerSheet.swift
//  LYFESTYL
//
//  The + menu. Tapping the plus opens this sheet: pick what you're logging and
//  the guided flow helps you organize it, or choose Free write to just dump a
//  thought and let the app file it quietly behind the scenes. A category pushes
//  to GuidedEntryView in place; Free write hands back to the full-screen composer.
//

import SwiftUI

struct CategoryPickerSheet: View {
    let source: EntrySource
    /// Called when the user chooses Free write (the sheet dismisses itself first).
    let onFreeWrite: () -> Void

    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The picker opens as a half sheet; drilling into a category expands it to
    /// full height (and it settles back to half when you pop back out).
    @State private var detent: PresentationDetent = .medium

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var categories: [InsightCategory] {
        InsightCategory.allCases.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(categories) { category in
                            NavigationLink(value: category) {
                                categoryTile(category)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        onFreeWrite()
                        dismiss()
                    } label: {
                        freeWriteTile
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("NEW ENTRY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: InsightCategory.self) { category in
                destination(for: category)
                    .onAppear { detent = .large }
                    .onDisappear { detent = .medium }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Destination

    @ViewBuilder
    private func destination(for category: InsightCategory) -> some View {
        if category == .activity {
            // ACTIVITY gets the full workout logger (searchable exercises, sets, or
            // a free-written session the model organizes).
            ActivityLoggerView(source: source) { dismiss() }
        } else {
            GuidedEntryView(category: category, source: source) { note, subtag, fields in
                Task {
                    await store.addGuidedEntry(
                        note: note,
                        source: source,
                        category: category,
                        subtag: subtag,
                        fields: fields
                    )
                }
                dismiss()
            }
        }
    }

    // MARK: - Tiles

    private func categoryTile(_ category: InsightCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CategoryIcon(category: category, size: 40)
            Text(category.label)
                .categoryLabel(color: .appTextEmphasis)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .background(category.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var freeWriteTile: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.appTextEmphasis)
                .frame(width: 40, height: 40)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("FREE WRITE")
                    .categoryLabel(color: .appTextEmphasis)
                Text("Just dump a thought, we'll file it.")
                    .font(.footnote)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
