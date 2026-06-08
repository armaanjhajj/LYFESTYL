//
//  ModelStatusBanner.swift
//  LYFESTYL
//
//  Surfaces the on-device model's availability when it isn't ready (downloading,
//  Apple Intelligence off, ineligible). Always reassures that entries are saved.
//

import SwiftUI

struct ModelStatusBanner: View {
    let availability: InsightEngine.Availability

    private var tint: Color {
        switch availability {
        case .available:            Solar.green
        case .downloading:          Solar.blue
        case .appleIntelligenceOff: Solar.yellow
        case .deviceNotEligible:    Solar.orange
        case .unknown:              Solar.yellow
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: availability.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(availability.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text(availability.message)
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardSurface(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}
