//
//  MainTabView.swift
//  LYFESTYL
//
//  The app's surfaces, via a native TabView. LYFE is the journal, the full
//  entry history plus the create flow; STYL is cumulative health insight (trends).
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
    @Environment(HealthService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = MainTabView.initialSelection

    private static var initialSelection: Int {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LYFE_TAB"] == "log" { return 1 }
        if ProcessInfo.processInfo.environment["LYFE_TAB"] == "train" { return 3 }
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
            // The aggregated health surface: Garmin, Hevy and Apple Health in one place.
            Tab("TRAIN", systemImage: "figure.run.circle", value: 3) {
                HealthHubView()
            }
            Tab(value: 2, role: .search) {
                SearchView()
            }
        }
        .task(id: auth.userID) {
            guard let uid = auth.userID else { return }
            engine.prewarm()
            await store.configure(userID: uid)
            await health.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            engine.refreshAvailability()
            Task {
                await store.retryUnfinished()
                await health.refresh()
            }
        }
    }
}
