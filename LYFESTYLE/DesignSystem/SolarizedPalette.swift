//
//  SolarizedPalette.swift
//  LYFESTYL
//
//  The ONE source of truth for color. The entire app uses the Solarized **Light**
//  palette (CLAUDE.md §3.1), warm beige paper, never dark. Never reach for
//  Color.blue, system grays, or an off-palette hex anywhere else, reference
//  `Solar.*` / the semantic aliases.
//
//  Accents carry meaning through ICONS, FILLS, TINTS, CHART MARKS, BADGES and
//  large black-weight headers, never small body/caption text on the beige base
//  (green/blue fall short of 4.5:1 there). Text is always base01/base00/base1.
//

import SwiftUI

/// Raw Solarized palette. Hexes are exact per the canonical Solarized spec; the
/// light-mode surface/content roles are documented inline (CLAUDE.md §3.1).
nonisolated enum Solar {
    // Surfaces (light)
    static let base3 = Color(hex: 0xFDF6E3) // primary background, the beige, everywhere
    static let base2 = Color(hex: 0xEEE8D5) // elevated surfaces / cards / grouped sections / chips
    // Content / text (light-mode hierarchy)
    // Darkened ~15% from the canonical Solarized content tones for legibility on
    // the beige base, originals were 0x586E75 / 0x657B83 / 0x93A1A1.
    static let base01 = Color(hex: 0x4B5E63) // emphasized text, headers, primary labels
    static let base00 = Color(hex: 0x56696F) // primary body text
    static let base1  = Color(hex: 0x7D8989) // secondary / muted text, separators, placeholders
    // Deep Solarized tones, kept for palette completeness; NOT used as surfaces
    // on light. Do not introduce these as backgrounds/text.
    static let base0  = Color(hex: 0x839496)
    static let base02 = Color(hex: 0x073642)
    static let base03 = Color(hex: 0x002B36)
    // Main accents (define the brand)
    static let green   = Color(hex: 0x859900) // PRIMARY accent: app tint, brand, EXCELLENT
    static let blue    = Color(hex: 0x268BD2) // SECONDARY accent: informational, links, charts
    // Supporting accents (semantic moments only, ranks, chart series)
    static let cyan    = Color(hex: 0x2AA198) // GOOD
    static let yellow  = Color(hex: 0xB58900) // OKAY
    static let orange  = Color(hex: 0xCB4B16) // BAD
    static let red     = Color(hex: 0xDC322F) // AWFUL
    static let magenta = Color(hex: 0xD33682) // reserved, rare semantic use only
    static let violet  = Color(hex: 0x6C71C4) // reserved, rare semantic use only
}

/// Semantic aliases. Declared on `ShapeStyle where Self == Color` (the same way
/// SwiftUI declares `.red`/`.blue`) so the leading-dot form resolves reliably in
/// every ShapeStyle context, `.foregroundStyle(.appText)`, `.fill(.appAccent)`,
/// `.background(.appSurface)`, `.tint(.appAccent)`, and `Color.appText` still
/// works for explicit use. One source of truth for the mapping.
nonisolated extension ShapeStyle where Self == Color {
    /// App background, the beige paper (`base3`).
    static var appBackground: Color { Solar.base3 }
    /// Elevated surfaces, cards, grouped sections, chips (`base2`).
    static var appSurface: Color { Solar.base2 }
    /// Primary body text (`base00`).
    static var appText: Color { Solar.base00 }
    /// Emphasized text / headers / primary labels (`base01`).
    static var appTextEmphasis: Color { Solar.base01 }
    /// Secondary / muted text, separators, placeholders (`base1`).
    static var appTextMuted: Color { Solar.base1 }
    /// Lower-emphasis text, same muted tone on light (`base1`).
    static var appTextSubtle: Color { Solar.base1 }
    /// PRIMARY interactive tint / brand accent (`green`).
    static var appAccent: Color { Solar.green }
    /// SECONDARY accent, informational, links, secondary chart series (`blue`).
    static var appAccentSecondary: Color { Solar.blue }
}

nonisolated extension Color {
    /// Hex initializer (RGB, no alpha), `Color(hex: 0x268BD2)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
