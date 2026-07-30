//
//  EntryClassification.swift
//  LYFESTYL
//
//  Guided Generation schema (CLAUDE.md §1) for the ONE behind-the-scenes job the
//  on-device model still does: take a free-written entry and quietly file it under
//  a single lifestyle category with a clean title. No ranking, no judgment, no
//  estimated numbers, the model organizes, it never grades.
//
//  Schema version: 5 (see InsightSchema.version).
//

import FoundationModels

/// Where a free-written entry belongs, decided on-device. The app maps `"NONE"`
/// to a nil category (a free thought with nothing trackable).
@Generable
struct EntryClassification: Equatable {
    @Guide(description: "The single best lifestyle category for this entry, or NONE when it is a free thought with nothing trackable (a stray idea, a quote, a to-do). Pick exactly one. NUTRITION: food and drink. ACTIVITY: exercise and movement. SLEEP: how they slept. HEALTH: physical health, symptoms, illness, meds. MIND: mood, stress, focus, reflection. SOCIAL: time with family, friends, or a partner. When the entry touches more than one, choose the one it is most about.", .anyOf(["NUTRITION", "ACTIVITY", "SLEEP", "HEALTH", "MIND", "SOCIAL", "NONE"]))
    var category: String

    @Guide(description: "A short, clean 3 to 6 word title for this entry, plain and neutral, in the user's own voice. No preamble, no 'The user', no judgement, no rating, no advice, no em dashes. e.g. 'Lunch with a coworker' or 'Rough night of sleep'.")
    var title: String

    @Guide(description: "SOCIAL only: the specific relationship this is about, as a short lowercase subtag, e.g. 'partner', 'mother', 'close friend', 'coworker', 'family'. Leave nil for every other category.")
    var subtag: String?
}
