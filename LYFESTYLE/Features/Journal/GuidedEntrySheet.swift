//
//  GuidedEntrySheet.swift
//  LYFESTYL
//
//  The guided "help me organize this" form, shown after the user picks a category
//  from the + menu. A couple of short, tappable questions (all skippable) plus an
//  optional free-text note. Whatever the user taps or types becomes their OWN
//  organized fields on the entry, no AI, no judgment, no estimated numbers. The
//  tappable-chip UI mirrors the old Refine flow so it feels familiar.
//

import SwiftUI

struct GuidedEntryView: View {
    let category: InsightCategory
    let source: EntrySource
    /// Called when the user saves: their note, the derived subtag, and the
    /// answers as organized fields.
    let onSave: (_ note: String, _ subtag: String?, _ fields: [EntryField]) -> Void

    @State private var answers: [GuidedAnswer]
    @State private var note: String = ""

    init(
        category: InsightCategory,
        source: EntrySource,
        onSave: @escaping (String, String?, [EntryField]) -> Void
    ) {
        self.category = category
        self.source = source
        self.onSave = onSave
        let template = CategoryQuestionTemplate.template(for: category)
        _answers = State(initialValue: template.questions.map { GuidedAnswer(question: $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                ForEach($answers) { $answer in
                    questionBlock($answer)
                }

                noteBlock
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle(category.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.label)
                    .categoryLabel(color: .appTextEmphasis)
                Text("Tap what fits, or just write. Everything here is optional.")
                    .font(.footnote)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func questionBlock(_ answer: Binding<GuidedAnswer>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(answer.wrappedValue.question.prompt)
                .font(.headline)
                .foregroundStyle(.appTextEmphasis)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(answer.wrappedValue.question.options, id: \.self) { option in
                    chip(option, isSelected: answer.wrappedValue.selection == .option(option)) {
                        toggle(answer, to: .option(option))
                    }
                }
                if answer.wrappedValue.question.allowsFreeText {
                    chip("Something else", isSelected: answer.wrappedValue.selection.isOther) {
                        toggle(answer, to: .other)
                    }
                }
            }

            if answer.wrappedValue.selection.isOther {
                TextField("Type your answer", text: answer.otherText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.appTextEmphasis)
                    .tint(.appAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .cardSurface()
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ANYTHING ELSE")
                .blackCaps(.footnote, tracking: 1, color: .appTextMuted)
            TextField("Add a note (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.appTextEmphasis)
                .tint(.appAccent)
                .frame(minHeight: 80, alignment: .topLeading)
                .padding(14)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func chip(_ text: String, isSelected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.appBackground : .appTextEmphasis)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? category.accent : Color.appSurface,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    /// Tapping a selected chip again clears it (so every answer stays skippable).
    private func toggle(_ answer: Binding<GuidedAnswer>, to selection: GuidedAnswer.Selection) {
        if answer.wrappedValue.selection == selection {
            answer.wrappedValue.selection = .none
        } else {
            answer.wrappedValue.selection = selection
        }
    }

    private var canSave: Bool {
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return answers.contains { $0.resolvedAnswer != nil }
    }

    private func save() {
        var fields: [EntryField] = []
        var subtag: String?
        for answer in answers {
            guard let value = answer.resolvedAnswer else { continue }
            fields.append(EntryField(label: answer.question.label, value: value))
            if answer.question.feedsSubtag, subtag == nil {
                subtag = value
            }
        }
        onSave(note, subtag, fields)
    }
}

// MARK: - Guided answer

/// One guided question plus the user's in-progress answer.
private struct GuidedAnswer: Identifiable {
    let id = UUID()
    let question: GuidedQuestion
    var selection: Selection = .none
    var otherText: String = ""

    enum Selection: Equatable {
        case none
        case option(String)
        case other

        var isOther: Bool { self == .other }
    }

    var resolvedAnswer: String? {
        switch selection {
        case .none:
            return nil
        case .option(let value):
            return value
        case .other:
            let trimmed = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
