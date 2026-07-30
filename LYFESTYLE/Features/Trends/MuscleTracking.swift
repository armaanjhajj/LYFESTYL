//
//  MuscleTracking.swift
//  LYFESTYL
//
//  The STYL muscle-balance surface: a calm read of which body systems you've
//  trained lately and which have gone light, plus an on-device "suggest a session"
//  that fills the gaps. Built from your own logged workouts (see MuscleBalance),
//  never a score or a grade, just a reflection you can act on.
//

import SwiftUI

// MARK: - Recently trained card

struct MuscleBalanceCard: View {
    let entries: [JournalEntry]
    var windowDays: Int = 7

    private var balance: MuscleBalance { MuscleBalance(entries: entries, windowDays: windowDays) }

    var body: some View {
        let balance = balance
        let maxVolume = max(balance.systemLoads.map(\.volume).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECENTLY TRAINED")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                Text("\(windowDays) DAYS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(.appTextMuted)
            }

            VStack(spacing: 12) {
                ForEach(balance.systemLoads) { load in
                    systemRow(load, maxVolume: maxVolume)
                }
            }

            if !balance.neglected.isEmpty {
                Divider().overlay(Color.appTextMuted.opacity(0.2))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.appAccent)
                    Text("Light lately: \(balance.neglected.map { $0.label.capitalized }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func systemRow(_ load: BodySystemLoad, maxVolume: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: load.system.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(load.wasTrained ? load.system.accent : .appTextMuted)
                .frame(width: 30, height: 30)
                .background((load.wasTrained ? load.system.accent : Color.appTextMuted).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(load.system.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Spacer()
                    Text(trailingText(load))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.appTextMuted)
                }
                BalanceBar(fill: load.volume / maxVolume, color: load.system.accent, active: load.wasTrained)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(load.system.label), \(load.sets) sets\(load.wasTrained ? "" : ", not trained")")
    }

    private func trailingText(_ load: BodySystemLoad) -> String {
        guard load.wasTrained else { return "not yet" }
        let sets = "\(load.sets) set\(load.sets == 1 ? "" : "s")"
        switch load.lastTrainedDaysAgo {
        case 0:  return "\(sets) · today"
        case 1:  return "\(sets) · 1d ago"
        case let d?: return "\(sets) · \(d)d ago"
        default: return sets
        }
    }
}

/// A thin proportional bar. `fill` is 0...1 relative to the most-trained system.
private struct BalanceBar: View {
    let fill: Double
    let color: Color
    var active: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appTextMuted.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fill)) * geo.size.width)
                    .opacity(active ? 1 : 0)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Suggest a session (entry point button)

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
