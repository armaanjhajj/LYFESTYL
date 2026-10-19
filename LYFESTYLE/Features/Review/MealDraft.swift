//
//  MealDraft.swift
//  LYFESTYL
//
//  One meal between the shutter and the log. Holds the snapped frame (in memory
//  only) and the foods the model found, and decides which drawer to show:
//
//    analyzing   names stream in while the model works
//    review      confident result: itemized, editable, ready to log
//    search      low confidence or no food: suggestions plus a search bar
//    failed      the model errored; retry or search
//
//  When the draft goes away (logged or dismissed) the frame goes with it.
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class MealDraft: Identifiable {

    enum Phase: Equatable {
        case analyzing
        case review
        /// The optional message says why the person landed on search.
        case search(String?)
        case failed(String)
    }

    let id = UUID()
    /// The meal being edited, when this draft came from the history.
    let editing: MealEntry?

    private(set) var image: CGImage?
    var phase: Phase
    var items: [DraftItem]
    /// Whole-photo candidates when the model couldn't commit to anything.
    private(set) var suggestions: [DraftItem] = []
    /// Food names as they stream out of the model.
    private(set) var found: [String] = []
    /// When the meal was eaten: the snap, or the original log time. Never asked for.
    let loggedAt: Date

    @ObservationIgnored private var attempts = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// A fresh snap.
    init(image: CGImage) {
        self.image = image
        self.editing = nil
        self.phase = .analyzing
        self.items = []
        self.loggedAt = .now
    }

    /// Search or type a meal, no photo.
    init() {
        self.image = nil
        self.editing = nil
        self.phase = .search(nil)
        self.items = []
        self.loggedAt = .now
    }

    /// Reopen a logged meal.
    init(editing entry: MealEntry) {
        self.image = nil
        self.editing = entry
        self.phase = .review
        self.items = entry.items.map { DraftItem(food: $0) }
        self.loggedAt = entry.loggedAt
    }

    var canRetry: Bool { image != nil }
    var nutrition: Nutrition { items.map(\.food.nutrition).total }
    var foods: [FoodItem] { items.map(\.food) }

    // MARK: - Analysis

    func analyze(with analyzer: FoodAnalyzer) {
        guard let image else { return }
        task?.cancel()
        guard analyzer.status.canReadPhotos else {
            if case .unavailable(let message) = analyzer.status {
                phase = .search(message)
            } else {
                phase = .search("Photos can't be read on this iPhone. Search for the food instead.")
            }
            return
        }
        phase = .analyzing
        found = []
        // The first pass decodes greedily; a retry samples so it can disagree.
        let varied = attempts > 0
        attempts += 1
        task = Task { [weak self] in
            do {
                let result = try await analyzer.analyze(image, varied: varied) { names in
                    self?.found = names
                }
                guard !Task.isCancelled else { return }
                self?.apply(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(FoodAnalyzer.message(for: error))
            }
            analyzer.prewarm()
        }
    }

    private func apply(_ result: [DraftItem]) {
        if result.isEmpty {
            suggestions = []
            phase = .search("No food found in that photo. Search for it instead.")
        } else if result.allSatisfy(\.needsCheck) {
            // Nothing it's sure of: offer its guesses rather than pretending.
            suggestions = result
            items = []
            phase = .search("Not sure what this is. Pick the closest match or search.")
        } else {
            suggestions = []
            items = result
            phase = .review
        }
    }

    /// Stop any work and drop the frame. Called on log and on dismiss.
    func release() {
        task?.cancel()
        task = nil
        image = nil
    }

    // MARK: - Editing

    func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    func add(_ foods: [FoodItem]) {
        items.append(contentsOf: foods.map { DraftItem(food: $0) })
        if !items.isEmpty { phase = .review }
    }

    func replace(_ id: UUID, with foods: [FoodItem]) {
        guard let index = index(of: id), !foods.isEmpty else { return add(foods) }
        items.replaceSubrange(index...index, with: foods.map { DraftItem(food: $0) })
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// The person looked at it, so it no longer needs a check.
    func markChecked(_ id: UUID) {
        guard let index = index(of: id) else { return }
        items[index].confidence = nil
    }
}
