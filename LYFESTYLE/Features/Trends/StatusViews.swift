//
//  StatusViews.swift
//  LYFESTYL
//
//  Content components for the STYL surface. After the move away from AI judgment,
//  STYL no longer shows a qualitative "standing" ring, only neutral activity and
//  the measured (HealthKit) lane. This file holds the measured-metric tile, the
//  one place real numbers appear, always clearly attributed to Apple Health.
//

import SwiftUI

// MARK: - Measured metric tile (Apple-Health-style, for the measured lane)

struct MeasuredMetricTile: View {
    let metric: MeasuredMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(metric.kind.category.accent)
                Text(metric.kind.label)
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.display)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.appTextEmphasis)
                Text(metric.kind.unit)
                    .font(.caption2)
                    .foregroundStyle(.appTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.kind.label): \(metric.displayWithUnit), measured by Apple Health")
    }
}
