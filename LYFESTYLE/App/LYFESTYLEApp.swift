//
//  LYFESTYLEApp.swift
//  LYFESTYL
//
//  App entry. Builds the shared services, the SwiftData container mirrored to
//  the CloudKit private database, forces Solarized Light and the green tint.
//

import SwiftData
import SwiftUI

@main
struct LYFESTYLEApp: App {
    @State private var analyzer = FoodAnalyzer()
    @State private var camera = CameraController()
    @State private var goals = GoalStore()
    @State private var health = HealthService()
    @State private var profile = ProfileStore()

    private let container = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(analyzer)
                .environment(camera)
                .environment(goals)
                .environment(health)
                .environment(profile)
                .tint(.appAccent)
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }

    static let cloudContainerID = "iCloud.Moments.LYFESTYLE"

    /// CloudKit-mirrored store. If CloudKit can't be set up (no entitlement in a
    /// local build), fall back to a local-only store rather than refusing to run;
    /// meals still save and will be there if sync is configured later.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([MealEntry.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the meal store: \(error)")
        }
    }
}
