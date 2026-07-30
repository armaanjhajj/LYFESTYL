//
//  EntryRowView.swift
//  LYFESTYL
//
//  One entry in the LYFE history, an Apple-Journal-style rounded card. The WHOLE
//  card is tinted by the entry's single category, so the list reads as classed at
//  a glance, no per-category chips, no ranks. The footer carries the category tag,
//  timestamp and source. While an entry is still being filed it dims and shows the
//  cycling on-device "thinking" indicator.
//

import SwiftUI

struct EntryRowView: View {
    let entry: JournalEntry

    private var isProcessing: Bool {
        entry.status == .pending || entry.status == .processing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.listTitle)
                .font(.body.weight(.medium))
                .foregroundStyle(.appTextEmphasis)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            content

            Divider().overlay(Color.appTextMuted.opacity(0.25))

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(rowTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(isProcessing ? 0.6 : 1)
    }

    /// The whole card is faintly tinted by its category (or a neutral surface when
    /// it's an uncategorized free thought).
    private var rowTint: Color {
        if let category = entry.category {
            return category.accent.opacity(0.12)
        }
        return Color.appSurface
    }

    @ViewBuilder
    private var content: some View {
        switch entry.status {
        case .pending, .processing:
            ProcessingIndicator()
        case .failed:
            HStack(spacing: 7) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Solar.orange)
                Text("Saved, will file when ready")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
        case .processed:
            // A logged workout gets a compact movement summary; other entries lean
            // on the category tint + footer tag alone (no chip row).
            if let workout = entry.workout, !workout.exercises.isEmpty {
                HStack(spacing: 8) {
                    Text(workout.countSummary)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                    HStack(spacing: 4) {
                        ForEach(workout.systemsWorked) { system in
                            Circle()
                                .fill(system.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let category = entry.category {
                CategoryTag(category: category, subtag: entry.subtag)
            } else if entry.status == .processed {
                Text("NOTE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.6)
                    .foregroundStyle(.appTextMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: entry.source.symbolName)
                .font(.caption2)
                .foregroundStyle(.appTextMuted)
            Text(timestamp)
                .font(.caption)
                .foregroundStyle(.appTextMuted)
            // Chevron appears exactly when the row is openable (see JournalView.row).
            if entry.status == .processed || entry.status == .failed {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
        }
    }

    private var timestamp: String {
        entry.createdAt.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        )
    }
}

/// A compact category label: icon + name (+ optional subtag). Reads at a glance
/// without competing with the entry title.
struct CategoryTag: View {
    let category: InsightCategory
    var subtag: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(category.accent)
            Text(labelText)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.4)
                .foregroundStyle(.appTextEmphasis)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(category.accent.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtag.map { "\(category.label), \($0)" } ?? category.label)
    }

    private var labelText: String {
        if let subtag, !subtag.isEmpty {
            return "\(category.label) · \(subtag.uppercased())"
        }
        return category.label
    }
}
