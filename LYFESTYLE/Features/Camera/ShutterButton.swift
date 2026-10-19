//
//  ShutterButton.swift
//  LYFESTYL
//
//  The big ring, bottom center. There is no system shutter control for an
//  in-app camera, so this is a plain Button with a ring-shaped style.
//

import SwiftUI

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(ShutterStyle())
        .accessibilityLabel("Snap meal")
        .accessibilityHint("Photographs the food in view and estimates its calories")
    }
}

private struct ShutterStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.appOnMedia, lineWidth: 6)
            Circle()
                .fill(Color.appOnMedia.opacity(configuration.isPressed ? 0.55 : 0.18))
                .padding(10)
        }
        .frame(width: 84, height: 84)
        .contentShape(Circle())
        .scaleEffect(configuration.isPressed ? 0.9 : 1)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
