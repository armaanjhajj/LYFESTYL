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
    @State private var health: HealthService
    // The aggregation feature: connectors, the unified history, and the analysis.
    @State private var profile: AthleteProfile
    @State private var healthData: HealthDataStore
    @State private var units: UnitPreference

    init() {
        let engine = InsightEngine()
        let profile = AthleteProfile()
        _auth = State(initialValue: AuthManager())
        _engine = State(initialValue: engine)
        _store = State(initialValue: JournalStore(engine: engine))
        _health = State(initialValue: HealthService())
        _profile = State(initialValue: profile)
        _healthData = State(initialValue: HealthDataStore(profile: profile))
        _units = State(initialValue: UnitPreference())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(engine)
                .environment(store)
                .environment(health)
                .environment(profile)
                .environment(healthData)
                .environment(units)
                .tint(.appAccent)
                .preferredColorScheme(.light)
        }
    }
}
