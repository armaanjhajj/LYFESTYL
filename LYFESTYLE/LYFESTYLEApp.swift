//
//  LYFESTYLEApp.swift
//  LYFESTYL
//
//  App entry. Builds the shared @Observable objects, forces Solarized Light
//  app-wide, and sets the global tint to Solarized green (CLAUDE.md §3.1).
//

import SwiftUI

@main
struct LYFESTYLEApp: App {
    @State private var auth: AuthManager
    @State private var engine: InsightEngine
    @State private var store: JournalStore
    // The aggregation feature: connectors, the unified history, and the analysis.
    @State private var profile: AthleteProfile
    @State private var healthData: HealthDataStore
    @State private var units: UnitPreference

    init() {
        let engine = InsightEngine()
        let profile = AthleteProfile()
        let store = JournalStore(engine: engine)
        _auth = State(initialValue: AuthManager())
        _engine = State(initialValue: engine)
        _store = State(initialValue: store)
        _profile = State(initialValue: profile)
        let healthData = HealthDataStore(profile: profile)
        _healthData = State(initialValue: healthData)
        _units = State(initialValue: UnitPreference())

        // The journal promotes a free-written session into the unified training history rather
        // than storing it on the entry, so it needs to reach the health store.
        store.healthData = healthData
        healthData.preferredWeightUnit = UnitPreference().weightUnit
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(engine)
                .environment(store)
                .environment(profile)
                .environment(healthData)
                .environment(units)
                .tint(.appAccent)
                .preferredColorScheme(.light)
        }
    }
}
