//
//  MealExport.swift
//  LYFESTYL
//
//  The whole history as a CSV, handed to the share sheet. Built in memory when
//  the person taps Export; nothing is written to disk by the app.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct MealExport: Transferable {
    let rows: [(date: Date, items: [FoodItem])]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("LYFESTYL Meals.csv")
    }

    var csv: String {
        var lines = ["date,time,food,portion,servings,calories,protein_g,carbs_g,fat_g"]
        // Local wall-clock time, the way the meal was eaten, and numbers that
        // read the same in every language so commas stay column breaks.
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        let time = Date.ISO8601FormatStyle(timeZone: .current).time(includingFractionalSeconds: false)
        let posix = Locale(identifier: "en_US_POSIX")
        for row in rows.sorted(by: { $0.date < $1.date }) {
            for item in row.items {
                let n = item.nutrition
                lines.append([
                    row.date.formatted(day),
                    row.date.formatted(time),
                    Self.escape(item.name),
                    Self.escape(item.portion),
                    item.servings.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(posix)),
                    Self.whole(n.calories),
                    Self.whole(n.protein),
                    Self.whole(n.carbs),
                    Self.whole(n.fat),
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func whole(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "" }
        return String(Int(value.rounded()))
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
