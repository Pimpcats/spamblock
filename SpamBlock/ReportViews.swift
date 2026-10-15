import SwiftUI

/// Reporting a number that got through.
///
/// iOS doesn't let apps read the call log, so the number comes in by copy and
/// paste from Recents. Paste is a button as well as the usual menu, since the
/// field is easy to miss on a phone pad.
struct ReportNumberView: View {

    let isReported: (Int64) -> Bool
    let onReport: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The address book's numbers; empty without contacts access.
    @State private var contacts: [Int64] = []

    private var number: Int64? { ContactExemptions.phoneNumber(from: text) }

    private var problem: String? {
        guard !text.isEmpty else { return nil }
        guard let number else { return "That isn’t a complete US or Canadian number. It needs the area code." }
        if isReported(number) { return "You’ve already reported this number." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Phone number", text: $text)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.body.monospacedDigit())
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first else { return }
                        DispatchQueue.main.async { text = pasted }
                    }
                } footer: {
                    Text("In Phone › Recents, tap ⓘ next to the call, touch and hold the number, and choose Copy. Then paste it here.")
                }

                if let problem {
                    Section {
                        Text(problem).foregroundStyle(.secondary)
                    }
                } else if let number {
                    Section {
                        LabeledContent("Number", value: SpamReport(number: number).formatted)
                        if contacts.contains(number) {
                            Label("This number is in your contacts, so it will still ring here. Delete the contact if you want it blocked.",
                                  systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.callout)
                        }
                    } footer: {
                        Text("Blocked on this iPhone as soon as you report it, and added to the shared list if SpamBlock has a GitHub token.")
                    }
                }
            }
            .navigationTitle("Report a number")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                contacts = await Task.detached { ContactExemptions.sortedNumbers() }.value
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") {
                        if let number {
                            onReport(number)
                            dismiss()
                        }
                    }
                    .disabled(number == nil || problem != nil)
                }
            }
        }
    }
}

/// Connecting SpamBlock to the shared list with a GitHub token.
struct SharedListView: View {

    let hasToken: Bool
    let onSave: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

    private static let newTokenPage = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasToken ? "Paste a new token" : "Paste the token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Kept in this iPhone’s Keychain, and used only to file your reports on spamblock-data. Don’t share it or paste it anywhere else.")
                }

                Section {
                    Link("Open GitHub’s new token page", destination: Self.newTokenPage)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Name it SpamBlock and choose the longest expiration.")
                        Text("2. Repository access: Only select repositories, then spamblock-data.")
                        Text("3. Permissions: Issues, Read and write.")
                        Text("4. Generate the token, copy it, and paste it above.")
                    }
                    .font(.callout)
                } header: {
                    Text("Making a token")
                } footer: {
                    Text("Only reports filed by the owner of spamblock-data go on the shared list, so this works with the GitHub account that owns it.")
                }

                if hasToken {
                    Section {
                        Button("Remove the token", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    } footer: {
                        Text("Reports made after this stay on this iPhone only.")
                    }
                }
            }
            .navigationTitle("Shared list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(token)
                        dismiss()
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview("Report") {
    ReportNumberView(isReported: { _ in false }) { _ in }
}

#Preview("Shared list") {
    SharedListView(hasToken: false, onSave: { _ in }, onRemove: {})
}
