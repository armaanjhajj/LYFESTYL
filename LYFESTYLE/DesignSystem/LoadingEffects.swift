//
//  LoadingEffects.swift
//  LYFESTYL
//
//  How the app looks while it reads a photo. No spinners, no status words:
//  the frozen frame develops like a print, placeholders shimmer where foods
//  are about to land, and each food resolves out of a blur as it's written.
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

// MARK: - Developing photo

/// The snapped frame while it's being read: it comes in soft, dim and
/// nearly colorless, drifts slowly closer as color comes up, and snaps into
/// focus and full color the moment the result is ready. A photo developing,
/// not a progress bar.
struct DevelopingPhoto: View {
    let image: CGImage
    let isDeveloping: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 when just snapped, 1 when done.
    @State private var developed = 0.0
    @State private var pushedIn = false

    var body: some View {
        Color.clear
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.1 + 0.9 * developed)
                    .brightness(-0.14 * (1 - developed))
                    .blur(radius: reduceMotion ? 0 : 7 * (1 - developed))
                    .scaleEffect(pushedIn && !reduceMotion ? 1.05 : 1)
            }
            .clipped()
            .onAppear { isDeveloping ? develop() : finish() }
            .onChange(of: isDeveloping) { _, developing in
                developing ? develop() : finish()
            }
            .accessibilityHidden(true)
    }

    private func develop() {
        withAnimation(.easeOut(duration: 4)) { developed = 0.55 }
        withAnimation(.easeInOut(duration: 5)) { pushedIn = true }
    }

    private func finish() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            developed = 1
            pushedIn = false
        }
    }
}

// MARK: - Shutter flash

/// The brief white flash of a shutter, played once when a frame is taken.
struct ShutterFlash: View {
    let trigger: Int
    @State private var opacity = 0.0

    var body: some View {
        Color.appOnMedia
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) {
                opacity = 0.75
                withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
            }
    }
}
