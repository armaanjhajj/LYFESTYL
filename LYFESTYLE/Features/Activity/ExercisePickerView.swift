//
//  ExercisePickerView.swift
//  LYFESTYL
//
//  The searchable exercise catalog behind the ACTIVITY logger. Native .searchable
//  over a List: with no query it reads as sections grouped by body system; typing
//  flips it to a flat ranked result list. Tapping a row toggles it into the
//  selection, and Add hands the chosen movements back to the logger.
//

import SwiftUI

struct ExercisePickerView: View {
    /// Called with the exercises the user chose (the sheet dismisses itself first).
    let onAdd: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: [String] = []   // ordered exercise ids

    private var systems: [BodySystem] {
        BodySystem.allCases.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var searchResults: [Exercise] {
        ExerciseLibrary.shared.search(query)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    Section {
                        ForEach(searchResults) { row($0) }
                    } header: {
                        header("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    }
                } else {
                    ForEach(systems) { system in
                        let exercises = ExerciseLibrary.shared.exercises(in: system)
                        if !exercises.isEmpty {
                            Section {
                                ForEach(exercises) { row($0) }
                            } header: {
                                header(system.label)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("EXERCISES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addLabel) { commit() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    // MARK: - Pieces

    private var addLabel: String {
        selected.isEmpty ? "Add" : "Add (\(selected.count))"
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = selected.contains(exercise.id)
        return Button {
            toggle(exercise)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: exercise.equipment.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(exercise.group.accent)
                    .frame(width: 34, height: 34)
                    .background(exercise.group.accent.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.appTextEmphasis)
                        .multilineTextAlignment(.leading)
                    Text(exercise.muscleSummary)
                        .font(.caption)
                        .foregroundStyle(.appTextMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? exercise.group.accent : .appTextMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.appTextMuted.opacity(0.2))
    }

    // MARK: - Selection

    private func toggle(_ exercise: Exercise) {
        if let idx = selected.firstIndex(of: exercise.id) {
            selected.remove(at: idx)
        } else {
            selected.append(exercise.id)
        }
    }

    private func commit() {
        let chosen = selected.compactMap { ExerciseLibrary.shared.exercise(id: $0) }
        onAdd(chosen)
        dismiss()
    }
}
