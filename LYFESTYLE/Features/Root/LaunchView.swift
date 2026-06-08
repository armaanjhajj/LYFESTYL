//
//  LaunchView.swift
//  LYFESTYL
//
//  Shown while the persisted Supabase session is being restored.
//

import SwiftUI

struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 24) {
            LyfestylLogo(size: 64, accentSecondLine: true)
                .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.55))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: pulse
                )
            ProgressView()
                .tint(.appTextMuted)
        }
        .onAppear { if !reduceMotion { pulse = true } }
    }
}

#Preview {
    LaunchView().background(Color.appBackground)
}
