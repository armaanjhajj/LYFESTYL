//
//  VoiceOrb.swift
//  LYFESTYL
//
//  The reactive centerpiece of voice mode: a soft, living orb that breathes while
//  idle and visibly pulses, swells, and glows in time with your voice while it's
//  listening. Pure drawn content (no rebuilt system control), animated with
//  TimelineView so it runs smoothly without driving SwiftUI state. Solarized
//  accents only (§3.1).
//

import SwiftUI

/// Voice mode's current state, shared by the orb and the session model.
enum VoicePhase: Equatable {
    case idle        // not started / paused
    case listening   // mic open, reacting to the user's voice
    case finishing   // wrapping up

    var caption: String {
        switch self {
        case .idle:      "Getting ready"
        case .listening: "Listening"
        case .finishing: "Wrapping up"
        }
    }

    /// The orb's accent tones for this phase (Solarized only).
    var tones: [Color] {
        switch self {
        case .listening:        [Solar.green, Solar.cyan, Solar.blue]
        case .idle, .finishing: [Solar.base1, Solar.base0, Solar.base1]
        }
    }
}

struct VoiceOrb: View {
    /// Live audio level 0...1 from the mic while listening.
    var level: Double
    var phase: VoicePhase
    var size: CGFloat = 230

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            orb(t: t)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func orb(t: TimeInterval) -> some View {
        let tones = phase.tones
        // Reactivity: a gentle breath baseline plus a strong, snappy response to
        // the voice so it reads as clearly alive while listening.
        let lvl = (phase == .listening) ? max(0, min(1, level)) : 0
        let breathe = 1.0 + 0.03 * sin(t * 1.4)
        let react = lvl * 0.55
        let coreScale = breathe + react

        return ZStack {
            // Outer glow halo, brightening with the voice.
            Circle()
                .fill(
                    RadialGradient(colors: [tones[0].opacity(0.32 + lvl * 0.45), .clear],
                                   center: .center, startRadius: 0, endRadius: size * 0.64)
                )
                .scaleEffect(coreScale * 1.16 + lvl * 0.12)
                .blur(radius: 30)

            // A reactive ring that pushes outward as you speak.
            Circle()
                .stroke(tones[0].opacity(0.18 + lvl * 0.30), lineWidth: 2 + lvl * 4)
                .frame(width: size * 0.6, height: size * 0.6)
                .scaleEffect(1.0 + react * 0.7)

            // Three slow-orbiting blobs give the surface its living, swirling feel,
            // swinging wider with the voice.
            ForEach(0..<3, id: \.self) { i in
                let speed = 0.2 + Double(i) * 0.06
                let radius = size * (0.10 + 0.016 * Double(i)) * (1 + react * 1.6)
                let angle = t * speed * (i.isMultiple(of: 2) ? 1 : -1) + Double(i) * 2.1
                Circle()
                    .fill(tones[i % tones.count].opacity(0.55))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .blur(radius: 26)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }

            // Solid core with a soft sheen.
            Circle()
                .fill(
                    LinearGradient(colors: [tones[0], tones[min(1, tones.count - 1)]],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(colors: [.white.opacity(0.35), .clear],
                                           center: UnitPoint(x: 0.35, y: 0.3),
                                           startRadius: 0, endRadius: size * 0.3)
                        )
                )
                .scaleEffect(coreScale)
                .shadow(color: tones[0].opacity(0.3 + lvl * 0.25), radius: 18, y: 6)
        }
        .compositingGroup()
        // Snappy, slightly springy tracking so each syllable visibly moves the orb.
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.55), value: level)
        .animation(.smooth(duration: 0.45), value: phase)
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VStack(spacing: 40) {
            VoiceOrb(level: 0.7, phase: .listening)
            VoiceOrb(level: 0.0, phase: .idle, size: 120)
        }
    }
}
