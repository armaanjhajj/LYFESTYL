//
//  Components.swift
//  LYFESTYL
//
//  Reusable CONTENT components (cards, chips, empty states). Glass goes on
//  chrome only; these are content, so they use solid Solarized surfaces, never
//  `.glassEffect`.
//

import SwiftUI
import UIKit

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

// MARK: - Slider field

/// A value in a tinted pill you can tap to type, with a slider in the same
/// tint underneath. Used for every adjustable number in the app.
struct SliderField<Focus: Hashable>: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .appAccent
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    /// When typing past the top of the range, widen the slider to fit.
    var grows: Bool = false
    let focus: FocusState<Focus?>.Binding
    let id: Focus

    @State private var upper: Double?

    private var isFocused: Bool { focus.wrappedValue == id }
    private var top: Double { upper ?? range.upperBound }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .frame(width: 24)
                }
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)).grouping(.never))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.appTextEmphasis)
                        .frame(minWidth: 36)
                        .fixedSize()
                        .focused(focus, equals: id)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.appTextMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(tint.opacity(isFocused ? 0.22 : 0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5))
                .contentShape(Capsule())
                .onTapGesture { focus.wrappedValue = id }
                .animation(.snappy, value: isFocused)
            }
            Slider(
                value: Binding(
                    get: { min(max(value, range.lowerBound), top) },
                    set: { value = ($0 / step).rounded() * step }
                ),
                in: range.lowerBound...top
            )
            .tint(tint)
            .accessibilityLabel(title)
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: Int(value / (step * 5)))
        // The range is fixed once shown, so dragging never rescales the
        // slider under your thumb.
        .onAppear { if upper == nil { upper = range.upperBound } }
        .onChange(of: value) { _, new in
            guard grows, new > top else { return }
            let round = pow(10, max(1, (log10(new)).rounded(.down)))
            upper = (new * 1.5 / round).rounded(.up) * round
        }
    }
}

// MARK: - Avatar

/// A round profile picture: the photo if there is one, else initials, else a
/// person glyph, on the brand tint.
struct Avatar: View {
    let photo: UIImage?
    let initials: String
    var size: CGFloat = 88

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.appAccent.opacity(0.18)
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.appAccent)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .black))
                            .foregroundStyle(.appAccent)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
