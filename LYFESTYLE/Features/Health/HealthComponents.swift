//
//  HealthComponents.swift
//  LYFESTYL
//
//  Shared building blocks for the health surfaces: stat tiles, source chips, sparklines and
//  section headers.
//
//  Follows the project's design rules throughout: Solarized only via `Solar` and the semantic
//  aliases, SF Pro with ALL CAPS black-weight headers, solid surfaces for content (glass is
//  reserved for chrome), and native components wherever one exists.
//

import SwiftUI
import Charts

// MARK: - Section header

/// The standard ALL CAPS section label, with an optional trailing accessory.
struct HealthSectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                }
            }
            Spacer(minLength: 8)
            accessory()
        }
        .accessibilityElement(children: .combine)
    }
}

extension HealthSectionHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() })
    }
}

// MARK: - Source chip

/// Small attribution chip. Every figure in the app is traceable to a source, and this is how
/// the UI says so.
struct SourceChip: View {
    let source: DataSource
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.symbolName)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(source.label)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(source.accent)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(source.accent.opacity(0.14), in: Capsule())
        .accessibilityLabel("From \(source.label)")
    }
}

/// A row of source chips, deduplicated.
struct SourceChips: View {
    let sources: [DataSource]
    var compact: Bool = false

    var body: some View {
        let unique = Array(Set(sources)).sorted { $0.fieldPriority > $1.fieldPriority }
        HStack(spacing: 4) {
            ForEach(unique) { SourceChip(source: $0, compact: compact) }
        }
    }
}

// MARK: - Stat tile

/// One measured value, with its label and unit. Used across the dashboard grids.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    var symbolName: String?
    var accent: Color = Solar.blue
    /// A short comparison line, such as "up 4 from usual".
    var context: String?
    var tone: InsightTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(.appTextMuted)
                    // Long names such as "Respiratory Rate" need a second line rather than an
                    // ellipsis, which reads as a bug.
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.appTextMuted)
                }
            }
            if let context {
                Text(context)
                    .font(.caption2)
                    .foregroundStyle(tone == .neutral ? .appTextMuted : tone.accent)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit ?? "")\(context.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Sparkline

/// A compact line chart with an optional baseline rule. Used inside insight cards and metric
/// rows, where the shape matters more than the axis labels.
struct Sparkline: View {
    let series: InsightSeries
    var accent: Color = Solar.blue
    var height: CGFloat = 44
    var showBaseline: Bool = true

    var body: some View {
        Chart {
            if showBaseline, let baseline = series.baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.appTextMuted.opacity(0.5))
            }
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
            if let last = series.points.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Value", last.value)
                )
                .foregroundStyle(accent)
                .symbolSize(36)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: paddedDomain)
        .frame(height: height)
        // Catmull-Rom can overshoot the data range between points, and the area fill would
        // otherwise paint outside the chart frame and over the card edge.
        .clipped()
        .accessibilityHidden(true)
    }

    /// Pad the domain slightly so the line never touches the frame edge.
    private var paddedDomain: ClosedRange<Double> {
        guard let range = series.range else { return 0...1 }
        let span = range.upperBound - range.lowerBound
        let padding = max(span * 0.12, 0.001)
        return (range.lowerBound - padding)...(range.upperBound + padding)
    }
}

// MARK: - Evidence list

/// The numbers behind an insight, laid out as label and value rows.
struct EvidenceList: View {
    let evidence: [InsightEvidence]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(evidence) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.value)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                        if let context = item.context {
                            Text(context)
                                .font(.caption2)
                                .foregroundStyle(.appTextMuted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Confidence badge

struct ConfidenceBadge: View {
    let confidence: InsightConfidence

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: confidence.symbolName)
                .font(.system(size: 9, weight: .semibold))
            Text(confidence.label)
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.4)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Confidence: \(confidence.label)")
    }

    private var color: Color {
        switch confidence {
        case .high:        Solar.green
        case .moderate:    Solar.yellow
        case .exploratory: Solar.base1
        }
    }
}

// MARK: - Empty and loading states

/// Shown when a surface has nothing yet, with the action that would change that.
struct HealthEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.appTextMuted)
            Text(title)
                .blackCaps(.title3, tracking: 0.8, color: .appTextEmphasis)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

// MARK: - Progress ring

/// A simple ring used for zone distribution and volume shares. Content, so it is a solid fill
/// rather than glass.
struct MetricRing: View {
    /// Fractions summing to at most 1, with their colours.
    let segments: [(fraction: Double, color: Color)]
    var lineWidth: CGFloat = 10
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appTextMuted.opacity(0.15), lineWidth: lineWidth)
            ForEach(Array(cumulative.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var cumulative: [(start: Double, end: Double, color: Color)] {
        var running = 0.0
        var result: [(Double, Double, Color)] = []
        for segment in segments {
            let start = running
            running = min(1, running + max(0, segment.fraction))
            guard running > start else { continue }
            result.append((start, running, segment.color))
        }
        return result
    }
}

// MARK: - Zone bar

/// Time in each heart-rate zone, as a stacked horizontal bar.
struct ZoneBar: View {
    let distribution: ZoneDistribution
    var height: CGFloat = 10

    /// Zone colours run cool to warm, which reads as easy to hard without needing a legend.
    static let zoneColors: [Color] = [Solar.cyan, Solar.blue, Solar.green, Solar.yellow, Solar.red]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(0..<ZoneDistribution.zoneCount, id: \.self) { zone in
                    let fraction = distribution.fraction(zone: zone)
                    if fraction > 0 {
                        Rectangle()
                            .fill(Self.zoneColors[zone])
                            .frame(width: max(1, geometry.size.width * fraction))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        (0..<ZoneDistribution.zoneCount)
            .filter { distribution.fraction(zone: $0) > 0.01 }
            .map { "Zone \($0 + 1), \(Formatting.percent(fraction: distribution.fraction(zone: $0)))" }
            .joined(separator: ", ")
    }
}

// MARK: - Connection status row

/// One connector's state, used on the connections screen and the dashboard prompt.
struct ConnectionRow: View {
    let source: DataSource
    let state: HealthDataStore.ConnectionState
    let subtitle: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(source.accent)
                .frame(width: 36, height: 36)
                .background(source.accent.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.label.uppercased())
                    .blackCaps(.subheadline, tracking: 0.6, color: .appTextEmphasis)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(state.errorText != nil ? Solar.red : .appTextMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            switch state {
            case .connecting:
                ProgressView().controlSize(.small)
            case .syncing(let progress, _):
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Solar.green)
            default:
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.label), \(statusText)")
    }

    private var statusText: String {
        switch state {
        case .notConnected:
            return subtitle
        case .connecting:
            return "Connecting"
        case .syncing(_, let detail):
            return detail ?? "Syncing"
        case .connected(let lastSync, let count):
            var parts: [String] = []
            if count > 0 { parts.append("\(count) session\(count == 1 ? "" : "s")") }
            if let lastSync {
                parts.append("synced \(Formatting.relativeDay(lastSync).lowercased())")
            }
            return parts.isEmpty ? "Connected" : parts.joined(separator: ", ")
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Card surface helper

extension View {
    /// A content card matching the app's existing surface treatment.
    func healthCard(padding: CGFloat = 16) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
