//
//  DataSource.swift
//  LYFESTYL
//
//  Provenance. Every unified record carries the origin it was normalized from, so
//  the UI can attribute a number honestly ("from Garmin", "from Hevy") and the
//  merge logic can pick a winner when two sources describe the same session.
//
//  The honesty rule (CLAUDE.md) extends to aggregation: we never blend two
//  sources into one unattributed figure. One source wins per field, and we say
//  which.
//

import SwiftUI

/// Where a unified record came from.
nonisolated enum DataSource: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    /// Garmin Connect, reached through Apple Health (the Garmin Connect app
    /// mirrors watch data into HealthKit) or through a direct Garmin sync.
    case garmin
    /// Hevy, via its public REST API.
    case hevy
    /// Apple Health itself: iPhone, Apple Watch, or any other writing app.
    case appleHealth
    /// Logged by hand inside LYFESTYL.
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .garmin:      "Garmin"
        case .hevy:        "Hevy"
        case .appleHealth: "Apple Health"
        case .manual:      "Logged here"
        }
    }

    var symbolName: String {
        switch self {
        case .garmin:      "applewatch.side.right"
        case .hevy:        "dumbbell.fill"
        case .appleHealth: "heart.fill"
        case .manual:      "square.and.pencil"
        }
    }

    var accent: Color {
        switch self {
        case .garmin:      Solar.blue
        case .hevy:        Solar.violet
        case .appleHealth: Solar.magenta
        case .manual:      Solar.base1
        }
    }

    /// Trust order when two sources describe the same session and we must keep one
    /// field. A dedicated device beats a phone-derived estimate; a purpose-built
    /// lifting log beats a generic strength workout.
    ///
    /// Higher wins.
    var fieldPriority: Int {
        switch self {
        case .garmin:      3   // chest strap / wrist optical + GPS, richest endurance data
        case .hevy:        3   // authoritative for sets, reps and load
        case .appleHealth: 2
        case .manual:      1
        }
    }

    /// Whether this source is a connector the user explicitly links (drives the
    /// Connections screen). `manual` and `appleHealth` are not "accounts".
    var isLinkableAccount: Bool {
        switch self {
        case .garmin, .hevy: true
        case .appleHealth, .manual: false
        }
    }
}

/// A source that a specific piece of data is attributed to, plus the identifier it
/// carried in that system. Keeping the foreign id lets an incremental sync update
/// a record in place rather than duplicating it.
nonisolated struct SourceRef: Codable, Hashable, Sendable {
    var source: DataSource
    /// The identifier in the origin system (Hevy workout UUID, HealthKit sample
    /// UUID, Garmin activity id). Unique within `source`.
    var foreignID: String
    /// The origin's own last-modified stamp, when it exposes one. Used to decide
    /// whether an incremental sync actually needs to rewrite the record.
    var updatedAt: Date?

    init(source: DataSource, foreignID: String, updatedAt: Date? = nil) {
        self.source = source
        self.foreignID = foreignID
        self.updatedAt = updatedAt
    }

    /// Globally unique key across all sources, used as the unified record id.
    var uniqueKey: String { "\(source.rawValue):\(foreignID)" }
}
