//
//  Formatting.swift
//  LYFESTYL
//
//  One place that turns canonical values (seconds, meters, meters per second,
//  kilograms) into the strings the UI shows. Canonical units are stored; every
//  imperial/metric decision happens here and nowhere else, so a user flipping their
//  preference never rewrites data.
//
//  Uses Foundation's own formatters and `Measurement` where they fit, so numbers
//  localize the way a first-party app's would.
//

import Foundation
import Observation

enum Formatting {

    // MARK: - Duration

    /// "1:24:06" for long sessions, "42:06" for short ones. Monospaced digits are
    /// applied by the caller's font, not here.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// "1h 24m" / "42m" / "35s", for places that read better in words.
    static func durationWords(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    // MARK: - Distance

    /// "8.42 km" or "5.23 mi", with the precision scaled to the magnitude so short
    /// intervals do not read as "0 km".
    static func distance(_ meters: Double, metric: Bool, includeUnit: Bool = true) -> String {
        guard meters.isFinite, meters >= 0 else { return includeUnit ? (metric ? "0 km" : "0 mi") : "0" }
        let value = metric ? meters / 1000 : meters / 1609.344
        let unit = metric ? "km" : "mi"
        let digits: Int = value < 10 ? 2 : (value < 100 ? 1 : 0)
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return includeUnit ? "\(number) \(unit)" : number
    }

    static func distanceUnit(metric: Bool) -> String { metric ? "km" : "mi" }

    /// Elevation, in whole meters or feet.
    static func elevation(_ meters: Double, metric: Bool) -> String {
        let value = metric ? meters : meters * 3.280839895
        let unit = metric ? "m" : "ft"
        return "\(Int(value.rounded())) \(unit)"
    }

    // MARK: - Pace and speed

    /// "4:38 /km" or "7:28 /mi" from a canonical seconds-per-kilometer value.
    static func pace(secondsPerKm: Double, metric: Bool, includeUnit: Bool = true) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        let perUnit = metric ? secondsPerKm : secondsPerKm * 1.609344
        // Beyond about 30 minutes per unit the reading is noise, not a pace.
        guard perUnit < 3600 else { return "--" }
        let total = Int(perUnit.rounded())
        let m = total / 60
        let s = total % 60
        let text = String(format: "%d:%02d", m, s)
        return includeUnit ? "\(text) /\(metric ? "km" : "mi")" : text
    }

    /// Pace from a speed in meters per second.
    static func pace(speedMps: Double, metric: Bool, includeUnit: Bool = true) -> String {
        guard speedMps > 0.1 else { return "--" }
        return pace(secondsPerKm: 1000 / speedMps, metric: metric, includeUnit: includeUnit)
    }

    /// "28.4 km/h" or "17.6 mph", the natural reading for cycling.
    static func speed(_ metersPerSecond: Double, metric: Bool) -> String {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return "--" }
        let value = metric ? metersPerSecond * 3.6 : metersPerSecond * 2.236936
        let unit = metric ? "km/h" : "mph"
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    /// "1:38 /100m" swim pace.
    static func swimPace(secondsPer100m: Double) -> String {
        guard secondsPer100m.isFinite, secondsPer100m > 0, secondsPer100m < 3600 else { return "--" }
        let total = Int(secondsPer100m.rounded())
        return String(format: "%d:%02d /100m", total / 60, total % 60)
    }

    // MARK: - Weight

    /// Volume load and other large weight figures: "12,450 kg" / "27,450 lb".
    static func weight(kilograms: Double, unit: WeightUnit, includeUnit: Bool = true) -> String {
        let value = unit.fromKilograms(kilograms)
        let digits: Int = value < 100 ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.automatic))
        return includeUnit ? "\(number) \(unit.rawValue)" : number
    }

    // MARK: - Plain numbers

    /// A count with thousands separators.
    static func count(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    /// A value rounded to a fixed number of decimals, no unit.
    static func decimal(_ value: Double, places: Int = 1) -> String {
        guard value.isFinite else { return "--" }
        return value.formatted(.number.precision(.fractionLength(places)))
    }

    /// A signed value, for deltas against a baseline: "+12", "-4".
    static func signed(_ value: Double, places: Int = 0, unit: String? = nil) -> String {
        guard value.isFinite else { return "--" }
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let body = abs(value).formatted(.number.precision(.fractionLength(places)))
        return unit == nil ? "\(sign)\(body)" : "\(sign)\(body) \(unit!)"
    }

    /// A percentage from a fraction: 0.184 becomes "18%".
    static func percent(fraction: Double, places: Int = 0) -> String {
        guard fraction.isFinite else { return "--" }
        return (fraction * 100).formatted(.number.precision(.fractionLength(places))) + "%"
    }

    /// A percentage from an already-scaled value: 18.4 becomes "18.4%".
    static func percentValue(_ value: Double, places: Int = 1) -> String {
        guard value.isFinite else { return "--" }
        return value.formatted(.number.precision(.fractionLength(places))) + "%"
    }

    // MARK: - Dates

    /// "Today", "Yesterday", or a short date. Weekday for the last week so the
    /// feed reads the way Apple's do.
    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch diff {
        case 0:      return "Today"
        case 1:      return "Yesterday"
        case 2...6:  return date.formatted(.dateTime.weekday(.wide))
        default:
            if calendar.component(.year, from: day) == calendar.component(.year, from: today) {
                return date.formatted(.dateTime.month(.abbreviated).day())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    /// "7:42 AM"
    static func timeOfDay(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "Mon 14 Jul · 7:42 AM"
    static func dayAndTime(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(timeOfDay(date))"
    }

    /// Hours and minutes for a sleep duration: "7h 24m".
    static func sleepDuration(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Unit preference

/// Whether the user reads distances in kilometers or miles, and weights in kg or
/// lb. Stored once and referenced everywhere, never inferred per screen.
@MainActor
@Observable
final class UnitPreference {
    private let distanceKey = "pref_distance_metric"
    private let weightKey = "pref_weight_unit"

    /// True for kilometers, false for miles.
    var isMetricDistance: Bool {
        didSet { UserDefaults.standard.set(isMetricDistance, forKey: distanceKey) }
    }

    var weightUnit: WeightUnit {
        didSet { UserDefaults.standard.set(weightUnit.rawValue, forKey: weightKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: distanceKey) != nil {
            isMetricDistance = defaults.bool(forKey: distanceKey)
        } else {
            // Default to the locale's own convention rather than assuming.
            isMetricDistance = Locale.current.measurementSystem != .us
        }
        if let raw = defaults.string(forKey: weightKey), let unit = WeightUnit(rawValue: raw) {
            weightUnit = unit
        } else {
            weightUnit = Locale.current.measurementSystem == .us ? .lb : .kg
        }
    }
}
