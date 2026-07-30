//
//  InsightCard.swift
//  LYFESTYL
//
//  How one insight is presented.
//
//  The card leads with the finding, then shows its shape, then the numbers behind it. That
//  order matters: the point is that a claim and its evidence arrive together, so nothing has
//  to be taken on trust. Low-confidence insights carry their caveat in words rather than being
//  quietly styled the same as a solid one.
//

import SwiftUI

struct InsightCard: View {
    let insight: HealthInsight
    var isExpanded: Bool = false
    var onToggle: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.appText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if let series = insight.series, !series.isEmpty {
                Sparkline(series: series, accent: insight.accent)
                    .padding(.top, 2)
            }

            if isExpanded, !insight.evidence.isEmpty {
                Divider().overlay(Color.appTextMuted.opacity(0.2))
                EvidenceList(evidence: insight.evidence)
                if let caveat = insight.confidence.caveat {
                    Text(caveat)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !insight.sources.isEmpty {
                    HStack(spacing: 6) {
                        Text("FROM")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(.appTextMuted)
                        SourceChips(sources: insight.sources, compact: true)
                    }
                }
            }

            if !insight.evidence.isEmpty, let onToggle {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide the numbers" : "Show the numbers")
                            .font(.caption.weight(.semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(insight.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .healthCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(insight.headline)
        .accessibilityHint(insight.detail)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(insight.accent)
                .frame(width: 30, height: 30)
                .background(insight.accent.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(insight.headline)
                    .font(.subheadline)
                    .fontWeight(.black)
                    .tracking(0.4)
                    .foregroundStyle(.appTextEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                ConfidenceBadge(confidence: insight.confidence)
            }

            Spacer(minLength: 4)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.appTextMuted)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss this insight")
            }
        }
    }
}

// MARK: - Compact row

/// A one-line version for dense lists.
struct InsightRow: View {
    let insight: HealthInsight

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: insight.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(insight.accent)
                .frame(width: 28, height: 28)
                .background(insight.accent.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.headline)
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(0.3)
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(insight.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.appTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
