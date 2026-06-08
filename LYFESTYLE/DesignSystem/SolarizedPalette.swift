//
//  SolarizedPalette.swift
//  LYFESTYL
//
//  The ONE source of truth for color. The entire app uses the Solarized Dark
//  palette (CLAUDE.md §3.1). Never reach for Color.blue, system grays, or an
//  off-palette hex anywhere else — reference `Solar.*` / the semantic aliases.
//

import SwiftUI

/// Raw Solarized Dark palette. Values are exact per CLAUDE.md §3.1.
enum Solar {
    // Base / backgrounds
    static let base03 = Color(hex: 0x002B36) // primary background
    static let base02 = Color(hex: 0x073642) // elevated surfaces / cards / grouped sections
    // Content / text
    static let base01 = Color(hex: 0x586E75) // secondary / muted text, separators
    static let base00 = Color(hex: 0x657B83) // body text (lower emphasis)
    static let base0  = Color(hex: 0x839496) // primary body text
    static let base1  = Color(hex: 0x93A1A1) // emphasized text
    // Accents
    static let yellow  = Color(hex: 0xB58900)
    static let orange  = Color(hex: 0xCB4B16)
    static let red     = Color(hex: 0xDC322F)
    static let magenta = Color(hex: 0xD33682)
    static let violet  = Color(hex: 0x6C71C4)
    static let blue    = Color(hex: 0x268BD2) // primary accent / interactive tint
    static let cyan    = Color(hex: 0x2AA198)
    static let green   = Color(hex: 0x859900)
}

/// Semantic aliases. Declared on `ShapeStyle where Self == Color` (the same way
/// SwiftUI declares `.red`/`.blue`) so the leading-dot form resolves reliably in
/// every ShapeStyle context — `.foregroundStyle(.appText)`, `.fill(.appAccent)`,
/// `.background(.appSurface)`, `.tint(.appAccent)` — and `Color.appText` still
/// works for explicit use. One source of truth for the mapping.
extension ShapeStyle where Self == Color {
    /// App background (`base03`).
    static var appBackground: Color { Solar.base03 }
    /// Elevated surfaces — cards, grouped sections (`base02`).
    static var appSurface: Color { Solar.base02 }
    /// Primary body text (`base0`).
    static var appText: Color { Solar.base0 }
    /// Emphasized text / values (`base1`).
    static var appTextEmphasis: Color { Solar.base1 }
    /// Secondary / muted text and separators (`base01`).
    static var appTextMuted: Color { Solar.base01 }
    /// Lower-emphasis body text (`base00`).
    static var appTextSubtle: Color { Solar.base00 }
    /// Primary interactive tint (`blue`).
    static var appAccent: Color { Solar.blue }
}

extension Color {
    /// Hex initializer (RGB, no alpha) — `Color(hex: 0x268BD2)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
