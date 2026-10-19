//
//  HealthService.swift
//  LYFESTYL
//
//  Apple Health, both ways, both optional:
//    write  each logged meal as dietary energy, protein, carbs and fat samples
//    read   height, weight, age and sex to prefill the goal calculator
//
//  Every sample carries a sync identifier built from the meal's id, so editing
//  a meal replaces its samples and deleting a meal removes them, on any device.
//

import Foundation
import HealthKit
import Observation

@Observable
final class HealthService {

    /// Per device: Health permission is granted per device too.
    var isWritingEnabled: Bool {
        didSet { UserDefaults.standard.set(isWritingEnabled, forKey: Self.writeKey) }
    }

    let isAvailable = HKHealthStore.isHealthDataAvailable()

    @ObservationIgnored private let store = HKHealthStore()
    private static let writeKey = "health.writeEnabled"

    private static let nutritionTypes: [(Macro, HKQuantityType, HKUnit)] = [
        (.calories, HKQuantityType(.dietaryEnergyConsumed), .kilocalorie()),
        (.protein, HKQuantityType(.dietaryProtein), .gram()),
        (.carbs, HKQuantityType(.dietaryCarbohydrates), .gram()),
        (.fat, HKQuantityType(.dietaryFatTotal), .gram()),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.height),
        HKQuantityType(.bodyMass),
        HKCharacteristicType(.dateOfBirth),
        HKCharacteristicType(.biologicalSex),
    ]

    init() {
        isWritingEnabled = UserDefaults.standard.bool(forKey: Self.writeKey)
    }

    /// True if the person has allowed writing dietary energy.
    var canWrite: Bool {
        isAvailable && store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized
    }

    /// Ask once for everything the app uses. Returns whether writing is allowed.
    @discardableResult
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let share = Set(Self.nutritionTypes.map { $0.1 as HKSampleType })
        try? await store.requestAuthorization(toShare: share, read: Self.readTypes)
        return canWrite
    }

    // MARK: - Writing

    /// Write (or replace) one meal's totals.
    func save(mealID: UUID, at date: Date, title: String, nutrition: Nutrition) async {
        guard isWritingEnabled, canWrite else { return }
        // A newer version under the same sync identifier replaces the old sample.
        let version = NSNumber(value: Int(Date.now.timeIntervalSince1970 * 1000))
        let samples = Self.nutritionTypes.compactMap { macro, type, unit -> HKQuantitySample? in
            let value = nutrition[macro]
            guard value > 0 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value.rounded()),
                start: date,
                end: date,
                metadata: [
                    HKMetadataKeyFoodType: title,
                    HKMetadataKeySyncIdentifier: Self.syncID(mealID, macro),
                    HKMetadataKeySyncVersion: version,
                ]
            )
        }
        // A macro that dropped to zero must lose its old sample too.
        let zeroed = Self.nutritionTypes.filter { nutrition[$0.0] <= 0 }.map(\.0)
        await delete(mealIDs: [mealID], only: zeroed)
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    /// Remove the samples written for these meals.
    func delete(mealIDs: [UUID]) async {
        await delete(mealIDs: mealIDs, only: Macro.allCases)
    }

    private func delete(mealIDs: [UUID], only macros: [Macro]) async {
        guard isAvailable, !mealIDs.isEmpty, !macros.isEmpty, canWrite else { return }
        for (macro, type, _) in Self.nutritionTypes where macros.contains(macro) {
            let ids = mealIDs.map { Self.syncID($0, macro) }
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ids)
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    private static func syncID(_ mealID: UUID, _ macro: Macro) -> String {
        "\(mealID.uuidString).\(macro.rawValue)"
    }

    // MARK: - Reading

    /// Whatever Health knows about the person, laid over `profile`.
    func fillProfile(_ profile: BodyProfile) async -> BodyProfile {
        guard isAvailable else { return profile }
        await requestAccess()
        var result = profile
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .female: result.sex = .female
            case .male:   result.sex = .male
            default:      break
            }
        }
        if let birth = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: birth),
           let years = Calendar.current.dateComponents([.year], from: date, to: .now).year, years > 0 {
            result.age = years
        }
        if let cm = await latest(.height, unit: .meterUnit(with: .centi)) { result.heightCm = cm }
        if let kg = await latest(.bodyMass, unit: .gramUnit(with: .kilo)) { result.weightKg = kg }
        return result
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }
}
