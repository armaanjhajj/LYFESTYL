//
//  RootView.swift
//  LYFESTYL
//
//  The camera is the whole app. First launch covers it with onboarding, and
//  the camera isn't built until that's done, so its permission prompt comes
//  after setup instead of over it.
//

import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.v2.done") private var onboarded = false

    var body: some View {
        Group {
            if onboarded {
                CameraScreen(isActive: true)
            } else {
                Color.appBackground.ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { onboarded = true }
        }
    }
}
