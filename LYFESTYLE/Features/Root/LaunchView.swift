//
//  LaunchView.swift
//  LYFESTYL
//
//  Shown while the persisted sign-in session is being restored.
//

import SwiftUI

struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 180, height: 180)
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.6))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { if !reduceMotion { pulse = true } }
    }
}

#Preview {
    LaunchView().background(Color.appBackground)
}
