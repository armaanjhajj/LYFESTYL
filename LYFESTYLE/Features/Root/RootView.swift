//
//  RootView.swift
//  LYFESTYL
//
//  Top-level routing: setup-needed → onboarding → sign-in → the app. Auth-gated.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if !auth.isConfigured {
                SetupNeededView()
            } else {
                switch auth.phase {
                case .loading:
                    LaunchView()
                case .signedOut:
                    if didOnboard {
                        SignInView()
                    } else {
                        OnboardingView { didOnboard = true }
                    }
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: auth.phase)
    }
}
