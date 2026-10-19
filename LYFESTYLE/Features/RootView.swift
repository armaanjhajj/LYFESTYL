//
//  RootView.swift
//  LYFESTYL
//
//  The camera is the whole app. First launch covers it with onboarding.
//

import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.done") private var onboarded = false

    var body: some View {
        CameraScreen(isActive: onboarded)
            .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
                OnboardingView { onboarded = true }
            }
    }
}
