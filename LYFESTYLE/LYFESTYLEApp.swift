//
//  LYFESTYLEApp.swift
//  LYFESTYL
//
//  App entry. Builds the shared @Observable objects, forces Solarized Dark
//  app-wide, and sets the global tint to Solarized blue (CLAUDE.md §3.1).
//

import SwiftUI

@main
struct LYFESTYLEApp: App {
    @State private var auth: AuthManager
    @State private var engine: InsightEngine
    @State private var store: JournalStore

    init() {
        let engine = InsightEngine()
        _auth = State(initialValue: AuthManager())
        _engine = State(initialValue: engine)
        _store = State(initialValue: JournalStore(engine: engine))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(engine)
                .environment(store)
                .tint(.appAccent)
                .preferredColorScheme(.dark)
        }
    }
}
