import SwiftUI

/// Entry sheet for a new rule.
///
/// The preview updates on every keystroke because prefix length is the one
/// decision that matters here: three digits is a whole area code and 7.9
/// million numbers, six digits is a single exchange and 10,000. Showing the
/// count as it's typed makes that trade visible before it becomes an error
/// message from iOS.
struct AddRuleView: View {

    let existingPrefixes: Set<String>
    /// Whether a prefix still fits in the parts alongside the current list.
    let hasRoom: (String) -> Bool
    /// How many whole area codes fit, for saying what the limit is.
    let areaCodeCapacity: Int
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var note = ""
    @FocusState private var isDigitsFocused: Bool

    private var validation: Result<String, RuleValidationError> {
        PrefixValidator.validate(digits, existingPrefixes: existingPrefixes)
    }

    private var validPrefix: String? {
        if case .success(let prefix) = validation { return prefix }
        return nil
    }

    /// A valid prefix there's no room for: every part is full, and iOS would
    /// reject the whole list rather than just this addition.
    private var isOverCapacity: Bool {
        guard let prefix = validPrefix else { return false }
        return !hasRoom(prefix)
    }

    private var validationError: RuleValidationError? {
        // Nothing typed yet isn't a mistake, so it isn't flagged as one.
        guard !digits.isEmpty, case .failure(let error) = validation else { return nil }
        return error
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Area code, e.g. 415", text: $digits)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                        .focused($isDigitsFocused)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Three digits blocks the whole area code. Add three more to block a single exchange — for example 415555 blocks (415) 555-0000 through (415) 555-9999.")
                }

                if let error = validationError {
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if isOverCapacity {
                    Section {
                        Label(
                            "There’s no room for that. SpamBlock holds up to \(areaCodeCapacity) whole area codes. Remove one first, or block a single exchange by adding three more digits.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.callout)
                    }
                }

                if let prefix = validPrefix {
                    Section("Will block") {
                        LabeledContent("Numbers like", value: PrefixValidator.formatted(prefix))
                        LabeledContent("Range", value: PrefixValidator.scopeDescription(prefix))
                        LabeledContent(
                            "Count",
                            value: "\(NumberPlan.entryCount(for: prefix).formatted()) numbers"
                        )
                    }
                }
            }
            .navigationTitle("Block an area code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let prefix = validPrefix {
                            onSave(prefix, note.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                    }
                    .disabled(validPrefix == nil || isOverCapacity)
                }
            }
            .onAppear { isDigitsFocused = true }
        }
    }
}

#Preview {
    AddRuleView(existingPrefixes: [], hasRoom: { _ in true }, areaCodeCapacity: 5) { _, _ in }
}
