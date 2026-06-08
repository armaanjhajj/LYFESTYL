//
//  LyfestylLogo.swift
//  LYFESTYL
//
//  The logo: two four-letter words stacked into a tight square block, black
//  weight SF Pro, all caps (CLAUDE.md §3.3). The square read comes from the
//  block layout — NOT from a mono font. The font stays normal SF Pro.
//
//      LYFE
//      STYL
//

import SwiftUI

struct LyfestylLogo: View {
    /// Point size of the cap height for each row.
    var size: CGFloat = 34
    var color: Color = .appTextEmphasis
    /// Optional two-tone: tint the second row with the accent.
    var accentSecondLine: Bool = false

    private var lineFont: Font {
        // Fixed size + black weight; default (SF Pro) design.
        .system(size: size, weight: .black, design: .default)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("LYFE", color: color)
            row("STYL", color: accentSecondLine ? .appAccent : color)
        }
        // Pull the two rows together so they hug into a block.
        .lineSpacing(0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LYFESTYL")
    }

    private func row(_ text: String, color: Color) -> some View {
        Text(text)
            .font(lineFont)
            .tracking(size * 0.04)          // a hair of tracking so the block squares up
            .foregroundStyle(color)
            .textCase(.uppercase)
            .monospacedDigit()              // harmless; keeps any digits aligned
            // Negative vertical padding pulls the rows into a tight stack.
            .padding(.vertical, -size * 0.10)
            .fixedSize()
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VStack(spacing: 40) {
            LyfestylLogo(size: 56)
            LyfestylLogo(size: 40, accentSecondLine: true)
        }
    }
}
