//
//  Formatting.swift
//  LYFESTYL
//
//  One place that turns stored values into the strings the UI shows. Uses
//  Foundation's own formatters so numbers and dates localize the way a
//  first-party app's would.
//

import Foundation

nonisolated enum Formatting {

    // MARK: - Nutrition

    /// "1,240" (no unit), calories always read as whole numbers.
    static func calories(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    /// "92 g", whole grams. Precision beyond that is noise for an estimate.
    static func grams(_ value: Double, includeUnit: Bool = true) -> String {
        guard value.isFinite else { return "--" }
        let number = Int(value.rounded()).formatted(.number.grouping(.automatic))
        return includeUnit ? "\(number) g" : number
    }

    /// A macro value with its own unit: "1,240 cal" or "92 g".
    static func value(_ value: Double, for macro: Macro) -> String {
        macro == .calories ? "\(calories(value)) cal" : grams(value)
    }

    /// "1×", "1.5×", "0.25×" for a servings multiplier.
    static func servings(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    /// "P 32 · C 48 · F 12", the compact macro line under a food.
    static func macroLine(protein: Double, carbs: Double, fat: Double) -> String {
        "P \(grams(protein, includeUnit: false)) · C \(grams(carbs, includeUnit: false)) · F \(grams(fat, includeUnit: false))"
    }

    // MARK: - Plain numbers

    /// A percentage from a fraction: 0.184 becomes "18%".
    static func percent(fraction: Double) -> String {
        guard fraction.isFinite else { return "--" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
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

    /// "Mon" for chart axes.
    static func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}
