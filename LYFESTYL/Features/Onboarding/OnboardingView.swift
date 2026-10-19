//
//  OnboardingView.swift
//  LYFESTYL
//
//  First launch only. The app icon and one button. Goals start at sensible
//  defaults and live in Settings.
//

import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 140 * 0.2237, style: .continuous))
                .shadow(color: Color.appTextEmphasis.opacity(0.15), radius: 18, y: 8)
                .accessibilityLabel("LYFESTYL")
            Spacer()
            Button(action: onDone) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
        .tint(.appAccent)
    }
}
