//
//  MuscleTracking.swift
//  LYFESTYL
//
//  The STYL muscle-balance surface: a calm read of which body systems you've
//  trained lately and which have gone light, plus an on-device "suggest a session"
//  that fills the gaps. Built from the unified training history,
//  never a score or a grade, just a reflection you can act on.
//

import SwiftUI

// MARK: - Recently trained card

/// Weekly sets by region, from the unified training history. Whatever the source, a set counts
/// the same, so this reads across Hevy, a watch and sessions logged here without distinction.
struct MuscleBalanceCard: View {
    let volumes: [MuscleVolume]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthSectionHeader(
                titled: "WEEKLY SETS BY REGION",
                subtitle: "Last 28 days, against the 10 to 20 set reference"
            ) { EmptyView() }
            MuscleVolumeChart(volumes: volumes)
                .frame(height: CGFloat(volumes.count) * 22 + 20)
        }
        .healthCard()
    }
}

struct SuggestSessionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.appAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.appAccent.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ASK YOUR COACH")
                        .blackCaps(.subheadline, tracking: 0.6, color: .appTextEmphasis)
                    Text("Plan a session or chat, private and on device")
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
