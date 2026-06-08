//
//  OnboardingView.swift
//  LYFESTYL
//
//  A short, one-time welcome that sets up the thesis: dump anything → on-device
//  AI structures it → private trends. Shown once before sign-in.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        .init(symbol: "text.bubble.fill", tint: Solar.blue,
              title: "JUST DUMP IT",
              body: "Type or talk like a voice memo. “Woke up sore, ran a mile, ate like garbage.” No forms, no fields, no friction."),
        .init(symbol: "cpu.fill", tint: Solar.green,
              title: "ON-DEVICE AI",
              body: "Apple's on-device model breaks every entry into nutrition, activity, sleep, and health — with real estimates. No servers, no API keys, no cost."),
        .init(symbol: "lock.shield.fill", tint: Solar.violet,
              title: "PRIVATE BY DESIGN",
              body: "The analysis never leaves your phone. Your structured history syncs to your own account so you can watch the trends build."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 72, weight: .regular))
                            .foregroundStyle(item.tint)
                        Text(item.title)
                            .blackCaps(.largeTitle, tracking: 1, color: .appTextEmphasis)
                            .multilineTextAlignment(.center)
                        Text(item.body)
                            .font(.body)
                            .foregroundStyle(.appText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(reduceMotion ? nil : .default) { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.appAccent)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .top) {
            LyfestylLogo(size: 30)
                .padding(.top, 12)
        }
    }
}

#Preview {
    OnboardingView(onDone: {}).background(Color.appBackground)
}
