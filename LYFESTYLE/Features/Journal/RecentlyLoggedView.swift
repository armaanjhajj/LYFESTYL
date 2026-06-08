//
//  RecentlyLoggedView.swift
//  LYFESTYL
//
//  The inline confirmation after logging: shows the entry being analyzed on
//  device, then reveals the structured breakdown with a calm staggered
//  animation. Tapping opens the full detail.
//

import SwiftUI

struct RecentlyLoggedView: View {
    let entry: JournalEntry
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JUST LOGGED")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)

            switch entry.status {
            case .pending, .processing:
                analyzing
            case .processed:
                revealed
            case .failed:
                failed
            }
        }
    }

    private var analyzing: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.appAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing on device…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text(entry.rawText)
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .cardSurface(padding: 16)
    }

    private var revealed: some View {
        NavigationLink(value: entry.id) {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = entry.overallSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.appTextEmphasis)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !entry.insights.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(entry.sortedInsights) { insight in
                            InsightMiniChip(category: insight.category, rank: insight.rank)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("View breakdown")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16)
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }

    private var failed: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Solar.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved — analysis will retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text("Your entry is safe. We'll break it down automatically when the model is ready.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Retry") {
                Task { await store.process(entryID: entry.id) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.appAccent)
        }
        .cardSurface(padding: 16)
    }
}
