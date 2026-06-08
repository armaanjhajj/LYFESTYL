//
//  EntryRowView.swift
//  LYFESTYL
//
//  A single entry in the Log: time, source, status, the model's summary, and the
//  category/rank chips — readable at a glance like an Apple Health list row.
//

import SwiftUI

struct EntryRowView: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.source.symbolName)
                    .font(.caption2)
                    .foregroundStyle(.appTextMuted)
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                Spacer()
                status
            }

            Text(entry.listTitle)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.insights.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.sortedInsights) { insight in
                        InsightMiniChip(category: insight.category, rank: insight.rank)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14)
    }

    @ViewBuilder
    private var status: some View {
        switch entry.status {
        case .processing, .pending:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini).tint(.appTextMuted)
                Text("Analyzing").font(.caption2).foregroundStyle(.appTextMuted)
            }
        case .failed:
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.caption)
                .foregroundStyle(Solar.orange)
        case .processed:
            EmptyView()
        }
    }
}
