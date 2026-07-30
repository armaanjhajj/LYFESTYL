//
//  LyfestylLogo.swift
//  LYFESTYL
//
//  The logo: two four-letter words stacked into a tight square block, black
//  weight SF Pro, all caps (CLAUDE.md §3.3). The square read comes from the
//  block layout, NOT from a mono font. The font stays normal SF Pro.
//
//      LYFE  ← green
//      STYL  ← blue
//
//  Two styles: `.twoTone` (primary, LYFE green, STYL blue, on beige) and
//  `.mono` (a single base01 tone for nav bars / very small sizes where two-tone
//  is too loud).
//

import SwiftUI

struct LyfestylLogo: View {
    /// The two words of the mark, used to point `.highlight` at the active tab.
    enum Word { case lyfe, styl }

    enum Style {
        /// LYFE green, STYL blue, the primary brand mark.
        case twoTone
        /// A single neutral tone (defaults to `base01`) for restrained contexts.
        case mono(Color)
        /// Just one word, in blue, reflects the current page (LYFE tab →
        /// `.single(.lyfe)`, STYL tab → `.single(.styl)`).
        case single(Word)

        static var mono: Style { .mono(.appTextEmphasis) }
    }

    /// Point size of the cap height for each row.
    var size: CGFloat = 34
    var style: Style = .twoTone

    private var lineFont: Font {
        // Fixed size + black weight; default (SF Pro) design.
        .system(size: size, weight: .black, design: .default)
    }

    private var topColor: Color {
        switch style {
        case .twoTone:     Solar.green
        case .mono(let c): c
        case .single:      Solar.blue
        }
    }

    private var bottomColor: Color {
        switch style {
        case .twoTone:     Solar.blue
        case .mono(let c): c
        case .single:      Solar.blue
        }
    }

    var body: some View {
        if case .single(let word) = style {
            // A single word stands alone (no stacked block) for the nav pill.
            row(word == .lyfe ? "LYFE" : "STYL", color: Solar.blue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(word == .lyfe ? "LYFE" : "STYL")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                row("LYFE", color: topColor)
                row("STYL", color: bottomColor)
            }
            // Pull the two rows together so they hug into a block.
            .lineSpacing(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("LYFESTYL")
        }
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
            LyfestylLogo(size: 56)                  // two-tone (default)
            LyfestylLogo(size: 40, style: .mono)    // single base01 tone
        }
    }
}
