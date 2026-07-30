//
//  MainTabView.swift
//  LYFESTYL
//
//  The app's surfaces, via a native TabView. LYFE is the one history: journal entries and
//  workouts from every source, plus the create flow. STYL is the one dashboard: readiness,
//  training load, insights and trends over everything the app knows.
//  The third tab uses `role: .search`, which renders as the separated Liquid Glass
//  search button on the trailing side of the tab bar (Apple Health style), all
//  free from the native component, no hand-rolled bar or search field (§2.1).
//  Configures the store for the signed-in user and retries unfinished pipeline
//  work whenever the app returns to the foreground.
//

import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(JournalStore.self) private var store
    @Environment(InsightEngine.self) private var engine
    @Environment(HealthDataStore.self) private var healthData
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = MainTabView.initialSelection

    private static var initialSelection: Int {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LYFE_TAB"] == "log" { return 1 }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            // Fill variants for the selected tab come for free, TabView swaps
            // each base symbol for its `.fill` variant on selection.
            Tab("LYFE", systemImage: "figure.mixed.cardio.circle", value: 0) {
                JournalView()
            }
            Tab("STYL", systemImage: "heart.circle", value: 1) {
                StylView()
            }
            Tab(value: 2, role: .search) {
                SearchView()
            }
        }
        .task(id: auth.userID) {
            guard let uid = auth.userID else { return }
            engine.prewarm()
            await store.configure(userID: uid)
            await healthData.loadCache()
            // Bring sessions logged before the unified model into the one history. Idempotent
            // and non-destructive, so running it every launch costs nothing once done.
            await healthData.migrateLegacyWorkouts(from: store.entries)
            await healthData.pullFromCloud()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            engine.refreshAvailability()
            Task {
                await store.retryUnfinished()
                await healthData.refreshAll()
            }
        }
    }
}
