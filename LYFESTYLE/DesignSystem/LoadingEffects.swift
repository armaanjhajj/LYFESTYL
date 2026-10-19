//
//  LoadingEffects.swift
//  LYFESTYL
//
//  How the app looks while it reads a photo. No spinners, no status words:
//  a scan line sweeps the frozen frame, placeholders shimmer where foods are
//  about to land, and each food resolves out of a blur as the model writes it.
//  Everything goes still under Reduce Motion.
//

import SwiftUI

// MARK: - Shimmer

extension View {
    /// A soft highlight that glides across the view, for content that's coming.
    func shimmering(_ active: Bool = true) -> some View {
        modifier(Shimmer(active: active))
    }
}

private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation) { timeline in
                    let period = 1.4
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.appBackground.opacity(0.75), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: -geo.size.width * 0.5 + phase * geo.size.width * 1.5)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

// MARK: - Skeleton

/// A rounded placeholder bar the size of the text it stands in for.
struct SkeletonBar: View {
    var width: CGFloat
    var height: CGFloat = 12

    var body: some View {
        Capsule()
            .fill(Color.appSurface)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Arrival

extension View {
    /// Resolve in from a blur and a small drop when first shown.
    func arrives(delay: Double = 0) -> some View {
        modifier(Arrival(delay: delay))
    }
}

private struct Arrival: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 10)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96, anchor: .leading)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) { shown = true }
            }
    }
}

// MARK: - Scan line

/// A line of light that sweeps up and down the frozen photo while it's read.
/// It stays in the part of the photo the drawer leaves visible.
struct ScanSweep: View {
    /// The top fraction of the screen to sweep.
    var coverage: CGFloat = 0.46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                Color.appAccent.opacity(0.08)
            } else {
                TimelineView(.animation) { timeline in
                    let period = 2.2
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    // Ease in and out at each end, like a scanner head.
                    let position = 0.5 - 0.5 * cos(t * 2 * .pi)
                    let y = geo.size.height * (0.08 + (coverage - 0.1) * position)
                    ZStack {
                        LinearGradient(
                            colors: [.clear, Color.appAccent.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 180)
                        .position(x: geo.size.width / 2, y: y)
                        Capsule()
                            .fill(Color.appOnMedia)
                            .frame(height: 2)
                            .shadow(color: Color.appAccent, radius: 8)
                            .shadow(color: Color.appAccent.opacity(0.6), radius: 20)
                            .padding(.horizontal, 12)
                            .position(x: geo.size.width / 2, y: y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}
