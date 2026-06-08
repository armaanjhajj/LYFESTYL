//
//  MainTabView.swift
//  LYFESTYL
//
//  The two surfaces (CLAUDE.md §1): JOURNAL and LOG, via a native TabView (Liquid
//  Glass tab bar comes for free). Configures the store for the signed-in user and
//  retries unfinished pipeline work whenever the app returns to the foreground.
//

import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(JournalStore.self) private var store
    @Environment(InsightEngine.self) private var engine
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
            Tab("Journal", systemImage: "square.and.pencil", value: 0) {
                JournalView()
            }
            Tab("Log", systemImage: "chart.bar.doc.horizontal", value: 1) {
                LogView()
            }
        }
        .task(id: auth.userID) {
            guard let uid = auth.userID else { return }
            engine.prewarm()
            await store.configure(userID: uid)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            engine.refreshAvailability()
            Task { await store.retryUnfinished() }
        }
    }
}
