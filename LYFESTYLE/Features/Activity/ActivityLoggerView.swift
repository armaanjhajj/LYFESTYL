//
//  ActivityLoggerView.swift
//  LYFESTYL
//
//  The ACTIVITY logging modal, pushed in place when you pick ACTIVITY from the +
//  menu. One calm page: build a session from the searchable exercise library,
//  logging sets/reps/weight where you want the detail (a bare exercise still
//  counts). The note doubles as free-write: skip the exercises and just describe
//  the session, and the on-device model organizes it into the same structured
//  movements behind the scenes.
//
//  Saving hands the whole thing to the store, which files it as one ACTIVITY entry
//  and feeds the muscle balance in STYL.
//

import SwiftUI

struct ActivityLoggerView: View {
    let source: EntrySource
    /// Called once the entry is handed to the store (dismisses the whole + sheet).
    let onComplete: () -> Void

    @Environment(JournalStore.self) private var store

    @State private var exercises: [LoggedExercise] = []
    @State private var unit: WeightUnit = .lb
    @State private var note = ""
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            buildMode
                .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("ACTIVITY")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { chosen in
                for ex in chosen {
                    exercises.append(LoggedExercise(exerciseID: ex.id, name: ex.name, sets: []))
                }
            }
        }
    }

    // MARK: - Build mode

    private var buildMode: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EXERCISES")
                    .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
                Spacer()
                Picker("Unit", selection: $unit) {
                    ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 108)
            }

            if exercises.isEmpty {
                emptyBuild
            } else {
                ForEach(exercises.indices, id: \.self) { e in
                    exerciseCard(e)
                }
            }

            Button { showPicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Add exercises")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.appAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            noteBlock
        }
    }

    private var emptyBuild: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 30))
                .foregroundStyle(.appTextMuted)
            Text("Add the movements you did. Log as much or as little detail as you like.")
                .font(.footnote)
                .foregroundStyle(.appTextMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func exerciseCard(_ e: Int) -> some View {
        let logged = exercises[e]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(logged.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    if let ex = logged.exercise {
                        Text(ex.muscleSummary)
                            .font(.caption)
                            .foregroundStyle(.appTextMuted)
                    }
                }
                Spacer(minLength: 8)
                Button { removeExercise(e) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.appTextMuted)
                }
                .buttonStyle(.plain)
            }

            if !exercises[e].sets.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(exercises[e].sets.enumerated()), id: \.element.id) { s, _ in
                        setRow(e, s)
                    }
                }
            }

            Button { addSet(e) } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.appAccent)
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }

    private func setRow(_ e: Int, _ s: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(s + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.appTextMuted)
                .frame(width: 18)
            numberField("Reps", repsBinding(e, s), keyboard: .numberPad)
            numberField("Weight", weightBinding(e, s), keyboard: .decimalPad)
            Text(unit.label)
                .font(.caption)
                .foregroundStyle(.appTextMuted)
            Spacer(minLength: 0)
            Button { removeSet(e, s) } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.appTextMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private func numberField(_ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.appTextEmphasis)
            .tint(.appAccent)
            .frame(width: 66)
            .padding(.vertical, 7)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTE")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            TextField(notePlaceholder, text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .tint(.appAccent)
                .frame(minHeight: exercises.isEmpty ? 120 : 60, alignment: .topLeading)
                .padding(14)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if exercises.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.appAccent)
                    Text("No exercises added? Just write your session here and we'll organize it into exercises for you.")
                        .font(.footnote)
                        .foregroundStyle(.appTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var notePlaceholder: String {
        exercises.isEmpty
            ? "Push day. Some barbell bench, a few sets of incline, then cable flys and tricep pushdowns."
            : "How it felt, anything worth remembering (optional)"
    }

    // MARK: - Set / exercise mutation

    private func addSet(_ e: Int) {
        exercises[e].sets.append(ExerciseSet())
    }

    private func removeSet(_ e: Int, _ s: Int) {
        guard exercises[e].sets.indices.contains(s) else { return }
        exercises[e].sets.remove(at: s)
    }

    private func removeExercise(_ e: Int) {
        guard exercises.indices.contains(e) else { return }
        exercises.remove(at: e)
    }

    private func repsBinding(_ e: Int, _ s: Int) -> Binding<String> {
        Binding(
            get: { exercises[e].sets[s].reps.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                exercises[e].sets[s].reps = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private func weightBinding(_ e: Int, _ s: Int) -> Binding<String> {
        Binding(
            get: {
                guard let w = exercises[e].sets[s].weight else { return "" }
                return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(w)
            },
            set: { newValue in
                let filtered = newValue.filter { $0.isNumber || $0 == "." }
                exercises[e].sets[s].weight = filtered.isEmpty ? nil : Double(filtered)
            }
        )
    }

    // MARK: - Save

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { !exercises.isEmpty || !trimmedNote.isEmpty }

    private func save() {
        if !exercises.isEmpty {
            // A built session; the note rides along as free-text context.
            Task { await store.addWorkout(note: note, exercises: exercises, unit: unit, source: source) }
        } else if !trimmedNote.isEmpty {
            // No structured exercises: let the on-device model organize the written
            // session into movements (kept alongside the raw note).
            Task { await store.addActivityNote(text: trimmedNote, source: source) }
        }
        onComplete()
    }
}
