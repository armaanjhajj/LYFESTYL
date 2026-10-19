//
//  Typography.swift
//  LYFESTYL
//
//  SF Pro only (the default system font), no Rounded, no Mono, no custom fonts.
//  Titles / headers / section headers / category labels are
//  ALL CAPS + black weight; body stays normal. These helpers keep that rule in
//  one place so screens just say `.sectionHeader()` etc.
//

import SwiftUI

extension View {
    /// ALL-CAPS, black-weight header with subtle positive tracking. The default
    /// font stays SF Pro, we only set weight/case/tracking.
    func blackCaps(_ font: Font, tracking: CGFloat = 0.5, color: Color = .appTextEmphasis) -> some View {
        self.font(font)
            .fontWeight(.black)
            .textCase(.uppercase)
            .tracking(tracking)
            .foregroundStyle(color)
    }

    /// Large screen title (navigation-style hero header inside content).
    func screenTitle(color: Color = .appTextEmphasis) -> some View {
        blackCaps(.largeTitle, tracking: 1, color: color)
    }

    /// Section header above a group of content.
    func sectionHeader(color: Color = .appText) -> some View {
        blackCaps(.headline, tracking: 0.8, color: color)
    }

    /// A category/label chip's text treatment.
    func categoryLabel(color: Color = .appTextEmphasis) -> some View {
        blackCaps(.subheadline, tracking: 0.8, color: color)
    }
}

/// The app's nav-bar header title (LYFE / STYL): ALL CAPS black-weight SF Pro in
/// Solarized blue (0x268BD2), sized to sit inline on the toolbar row, left of the
/// trailing actions, the way a native app aligns its header with the bar buttons.
struct NavHeaderTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title2)
            .fontWeight(.black)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Solar.blue)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// A reusable ALL-CAPS black-weight `Text` for titles where a plain view
/// modifier chain would be repetitive.
struct CapsTitle: View {
    let text: String
    var font: Font = .title2
    var tracking: CGFloat = 0.8
    var color: Color = .appTextEmphasis

    init(_ text: String, font: Font = .title2, tracking: CGFloat = 0.8, color: Color = .appTextEmphasis) {
        self.text = text
        self.font = font
        self.tracking = tracking
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(.black)
            .textCase(.uppercase)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

extension View {
    /// An inline navigation title in the house style, ALL CAPS black weight.
    /// The plain system title stays set underneath for VoiceOver and the back
    /// button's long-press menu.
    func capsNavigationTitle(_ title: String) -> some View {
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.black)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.appTextEmphasis)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
