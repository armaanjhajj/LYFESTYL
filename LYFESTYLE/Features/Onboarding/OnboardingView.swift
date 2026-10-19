//
//  OnboardingView.swift
//  LYFESTYL
//
//  First launch only. The logo, one line, one button. Goals start at sensible
//  defaults and live in Settings.
//

import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LyfestylLogo(size: 72)
            Text("Snap your food.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appTextMuted)
                .padding(.top, 20)
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
