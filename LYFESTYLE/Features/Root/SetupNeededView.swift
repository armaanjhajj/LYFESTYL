//
//  SetupNeededView.swift
//  LYFESTYL
//
//  Shown when Secrets.plist is missing or still has placeholder values. Keeps
//  the app from crashing and tells the user exactly what to paste where.
//

import SwiftUI

struct SetupNeededView: View {
    var body: some View {
        VStack(spacing: 28) {
            LyfestylLogo(size: 56, accentSecondLine: true)

            VStack(spacing: 12) {
                Text("ALMOST THERE")
                    .blackCaps(.title2, color: .appTextEmphasis)
                Text("Add your Supabase keys to finish setup. The on-device AI needs no key — only Supabase storage does.")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Copy", "Secrets.example.plist → LYFESTYLE/Secrets.plist")
                step(2, "Paste", "your Project URL and the publishable key (sb_publishable_…)")
                step(3, "Run", "build & launch again — you're in")
            }
            .cardSurface(padding: 18)
            .frame(maxWidth: 360)

            Text("Your secret key stays out of the app. Only the publishable key is used.")
                .font(.caption)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(28)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.black))
                .foregroundStyle(.appAccent)
                .frame(width: 26, height: 26)
                .background(Color.appAccent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).categoryLabel(color: .appTextEmphasis)
                Text(detail).font(.footnote).foregroundStyle(.appTextMuted)
            }
        }
    }
}

#Preview {
    SetupNeededView().background(Color.appBackground)
}
