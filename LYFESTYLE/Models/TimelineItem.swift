//
//  TimelineItem.swift
//  LYFESTYL
//
//  One entry in the app's single history.
//
//  Everything the user has recorded belongs in one chronological list: a thought they wrote, a
//  meal, a night's sleep, a lifting session from Hevy, a run from a watch, a workout they built
//  by hand. Splitting those across separate screens by where they came from is exactly the
//  seam this removes, and it is not a distinction the user ever thinks in.
//
//  The two cases are genuinely different SHAPES rather than different sources: an entry is
//  words the user wrote, a workout is a measured session. Anything that arrives as a workout,
//  from any source including this app's own logger, is a `.workout`.
//
//  A journal entry that was PROMOTED into a workout (the on-device model found a session in
//  what was written) is deliberately excluded, because the workout it produced already
//  represents it. Otherwise one logged session would appear twice.
//

import Foundation

nonisolated enum TimelineItem: Identifiable, Hashable, Sendable {
    case entry(JournalEntry)
    case workout(UnifiedWorkout)

    var id: String {
        switch self {
        case .entry(let entry):     "entry-\(entry.id.uuidString)"
        case .workout(let workout): "workout-\(workout.id)"
        }
    }

    /// When this happened, which is what the whole list is ordered by.
    var date: Date {
        switch self {
        case .entry(let entry):     entry.createdAt
        case .workout(let workout): workout.start
        }
    }

    /// The life category this belongs to. A workout is always ACTIVITY.
    var category: InsightCategory? {
        switch self {
        case .entry(let entry):     entry.category
        case .workout:              .activity
        }
    }

    /// Free text to match against when searching.
    var searchText: String {
        switch self {
        case .entry(let entry):
            [entry.listTitle, entry.rawText, entry.subtag ?? "",
             entry.fields.map { "\($0.label) \($0.value)" }.joined(separator: " ")]
                .joined(separator: " ")
        case .workout(let workout):
            [workout.title, workout.notes ?? "", workout.sport.label,
             workout.origin.source.label,
             (workout.strength?.exercises ?? []).map(\.name).joined(separator: " ")]
                .joined(separator: " ")
        }
    }

    var isWorkout: Bool {
        if case .workout = self { return true }
        return false
    }

    /// Only sessions logged in this app can be deleted here. A synced session would simply come
    /// back on the next refresh, so offering to delete it would be a lie.
    var isDeletable: Bool {
        switch self {
        case .entry:                true
        case .workout(let workout): workout.origin.source == .manual
        }
    }
}

// MARK: - Building the timeline

nonisolated extension TimelineItem {

    /// Interleave journal entries and workouts into one history, newest first.
    ///
    /// Entries already promoted into a workout are dropped, since that workout stands for them.
    /// The check is by id rather than by time so it stays correct even when a promotion and its
    /// entry are minutes apart.
    static func build(entries: [JournalEntry], workouts: [UnifiedWorkout]) -> [TimelineItem] {
        let promoted = Set(entries.compactMap(\.promotedWorkoutID))
        var items: [TimelineItem] = []
        items.reserveCapacity(entries.count + workouts.count)

        for entry in entries where entry.promotedWorkoutID == nil {
            // A legacy entry whose workout has been migrated is represented by that workout.
            if entry.category == .activity, entry.workout != nil,
               workouts.contains(where: { $0.id == LegacyWorkoutBridge.identity(for: entry.id).uniqueKey }) {
                continue
            }
            items.append(.entry(entry))
        }
        for workout in workouts {
            items.append(.workout(workout))
        }
        _ = promoted
        return items.sorted { $0.date > $1.date }
    }

    /// Group into calendar days, newest day first, for a sectioned list.
    static func groupedByDay(
        _ items: [TimelineItem],
        calendar: Calendar = .current
    ) -> [(day: Date, items: [TimelineItem])] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}
