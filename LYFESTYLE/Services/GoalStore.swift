//
//  GoalStore.swift
//  LYFESTYL
//
//  Goals and the body profile live in iCloud key-value storage, Apple's store
//  for small per-person settings, so a new phone starts with the same targets.
//  UserDefaults keeps a local copy so the app works signed out of iCloud.
//

import Foundation
import Observation

@Observable
final class GoalStore {
    private static let goalsKey = "goals.v1"
    private static let profileKey = "bodyProfile.v1"

    var goals: Goals {
        didSet { if goals != oldValue { write(goals, key: Self.goalsKey) } }
    }

    /// nil until the person fills in the calculator once.
    var profile: BodyProfile? {
        didSet { if profile != oldValue, let profile { write(profile, key: Self.profileKey) } }
    }

    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private let local = UserDefaults.standard
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        goals = Self.read(Goals.self, key: Self.goalsKey) ?? Goals()
        profile = Self.read(BodyProfile.self, key: Self.profileKey)
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromCloud() }
        }
        cloud.synchronize()
    }

    /// True once goals exist anywhere, which lets a second device skip setup.
    var hasStoredGoals: Bool {
        cloud.data(forKey: Self.goalsKey) != nil || local.data(forKey: Self.goalsKey) != nil
    }

    private func reloadFromCloud() {
        if let goals = Self.read(Goals.self, key: Self.goalsKey), goals != self.goals { self.goals = goals }
        if let profile = Self.read(BodyProfile.self, key: Self.profileKey), profile != self.profile { self.profile = profile }
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        cloud.set(data, forKey: key)
        local.set(data, forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
