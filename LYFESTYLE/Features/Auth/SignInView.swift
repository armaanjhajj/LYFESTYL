//
//  SignInView.swift
//  LYFESTYL
//
//  Sign in with Apple gate (CLAUDE.md §4.3). Uses the native SignInWithAppleButton
//  wired to Supabase via AuthManager — never a custom black Apple button.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                LyfestylLogo(size: 72, accentSecondLine: true)
                Text("Your lifestyle, made legible.")
                    .font(.title3)
                    .foregroundStyle(.appText)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                valueRow("text.bubble.fill", Solar.blue, "Dump a thought — typed or spoken")
                valueRow("cpu.fill", Solar.green, "On-device AI structures it instantly")
                valueRow("chart.xyaxis.line", Solar.cyan, "Watch your trends build over time")
            }
            .frame(maxWidth: 340, alignment: .leading)
            .padding(.bottom, 36)

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .frame(maxWidth: 340)

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Solar.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                Text("Private by design — your entries are analyzed on your device.")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
    }

    private func valueRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.appText)
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager())
        .background(Color.appBackground)
}
