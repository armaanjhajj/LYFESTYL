//
//  Components.swift
//  LYFESTYL
//
//  Reusable CONTENT components (cards, chips, empty states). Glass goes on
//  chrome only; these are content, so they use solid Solarized surfaces, never
//  `.glassEffect`.
//

import SwiftUI

// MARK: - Card surface

extension View {
    /// The standard elevated content surface: a base2 rounded card.
    func cardSurface(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Icon chip

/// An SF Symbol on a soft tinted rounded square, the Apple Health row icon.
struct IconChip: View {
    let symbol: String
    var tint: Color = .appAccent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.18),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
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
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 24)
    }
}

// MARK: - Flow layout (wraps pills onto multiple lines)
// A small Layout, there is no native wrapping stack, so this is a legitimate
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

// MARK: - Progress ring

/// A ring that fills toward a goal, like the Activity rings. The fill springs
/// to each new value, so streamed numbers sweep it around.
struct ProgressRing: View {
    /// 0...1; anything past 1 shows a full ring.
    let fraction: Double
    var tint: Color = .appAccent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Macro line

/// "20P  15C  5F" with each number in its macro's color, under a food.
struct MacroLine: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: 10) {
            part(protein, .protein, "P")
            part(carbs, .carbs, "C")
            part(fat, .fat, "F")
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Formatting.grams(protein)) protein, \(Formatting.grams(carbs)) carbs, \(Formatting.grams(fat)) fat")
    }

    private func part(_ value: Double, _ macro: Macro, _ letter: String) -> some View {
        HStack(spacing: 2) {
            Text(Formatting.grams(value, includeUnit: false))
                .foregroundStyle(macro.accent)
                .contentTransition(.numericText(value: value))
            Text(letter)
                .foregroundStyle(.appTextMuted)
        }
    }
}
