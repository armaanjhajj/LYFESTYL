//
//  Components.swift
//  LYFESTYL
//
//  Reusable CONTENT components (cards, badges, chips, pills). Per CLAUDE.md §2.2
//  glass goes on chrome only — these are content, so they use solid Solarized
//  surfaces (base02 cards, base03 insets), never `.glassEffect`.
//

import SwiftUI

// MARK: - Card surface

extension View {
    /// The standard elevated content surface: a base02 rounded card.
    func cardSurface(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Rank badge

struct RankBadge: View {
    let rank: Rank
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: rank.symbolName)
                .font(.caption2.weight(.bold))
            if !compact {
                Text(rank.label)
                    .font(.caption2)
                    .fontWeight(.black)
                    .tracking(0.6)
            }
        }
        .foregroundStyle(rank.color)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, 5)
        .background(rank.color.opacity(0.18), in: Capsule())
        .accessibilityLabel("Rank: \(rank.label)")
    }
}

// MARK: - Category icon chip

struct CategoryIcon: View {
    let category: InsightCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(category.accent)
            .frame(width: size, height: size)
            .background(
                category.accent.opacity(0.18),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Metric pill

struct MetricPill: View {
    let key: MetricKey
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: key.symbolName)
                .font(.caption2)
                .foregroundStyle(.appTextMuted)
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.appTextEmphasis)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appBackground, in: Capsule())
        .accessibilityLabel("\(key.label): \(text)")
    }
}

// MARK: - Insight card (one category within an entry)

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CategoryIcon(category: insight.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.category.label)
                        .categoryLabel(color: insight.category.accent)
                    if !insight.title.isEmpty {
                        Text(insight.title)
                            .font(.headline)
                            .foregroundStyle(.appTextEmphasis)
                    }
                }
                Spacer(minLength: 8)
                RankBadge(rank: insight.rank)
            }

            if !insight.detail.isEmpty {
                Text(insight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !insight.displayMetrics.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(insight.displayMetrics, id: \.key) { metric in
                        MetricPill(key: metric.key, text: metric.text)
                    }
                }
            }
        }
        .cardSurface()
    }
}

// MARK: - Insight mini chip (category icon + rank, compact)

struct InsightMiniChip: View {
    let category: InsightCategory
    let rank: Rank

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(category.accent)
            Text(rank.label)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.4)
                .foregroundStyle(rank.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.appBackground, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.label): \(rank.label)")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .appTextMuted

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(tint)
            Text(title)
                .blackCaps(.title3, tracking: 0.8, color: .appTextEmphasis)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 24)
    }
}

// MARK: - Flow layout (wraps pills onto multiple lines)
// A small Layout — there is no native wrapping stack, so this is a legitimate
// container, not a re-skinned system control.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += rowHeight + spacing
                rows.append([])
                rowWidth = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
