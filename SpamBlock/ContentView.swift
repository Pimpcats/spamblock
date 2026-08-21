import SwiftUI
import UIKit

struct ContentView: View {

    @StateObject private var list = BlockListViewModel()
    @StateObject private var directory = CallDirectoryController()
    @State private var isAddingRule = false

    var body: some View {
        NavigationStack {
            List {
                if !list.isEditable { compiledInListSection }
                statusSection
                blockListSection
                if let saveError = list.saveError {
                    Section {
                        messageRow(text: saveError, kind: .failure)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("SpamBlock")
            .toolbar {
                if list.isEditable {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingRule = true
                        } label: {
                            Label("Add area code", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingRule) {
                AddRuleView(existingPrefixes: list.existingPrefixes) { prefix, note in
                    list.add(prefix: prefix, note: note)
                }
            }
            .onAppear { directory.refreshStatus() }
            // Turning the extension on happens in Settings, outside the app, so
            // the switch is re-read every time the app comes back to the front.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                directory.refreshStatus()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if directory.status != .enabled {
                Button("Open call blocking settings") { directory.openSettings() }
            }

            Button(action: applyChanges) {
                HStack {
                    Text(list.hasUnappliedChanges ? "Update block list" : "Reload block list")
                    Spacer()
                    if directory.isReloading {
                        ProgressView()
                    } else if list.hasUnappliedChanges {
                        Text("Pending")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(directory.isReloading || list.rules.isEmpty)

            if let message = directory.message {
                messageRow(text: message.text, kind: message.kind)
            }
        } footer: {
            Text("iOS only blocks calls once SpamBlock is switched on under Settings › Phone › Call Blocking & Identification, and only after the list has been loaded.")
        }
    }

    private var statusIcon: String {
        switch directory.status {
        case .enabled: return "checkmark.shield.fill"
        case .disabled: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch directory.status {
        case .enabled: return .green
        case .disabled: return .orange
        case .unknown: return .secondary
        }
    }

    private var statusTitle: String {
        switch directory.status {
        case .enabled: return "Blocking is on"
        case .disabled: return "Blocking is off"
        case .unknown: return "Checking…"
        }
    }

    private var statusDetail: String {
        switch directory.status {
        case .enabled: return "iOS is using your block list."
        case .disabled: return "Switch SpamBlock on in Settings to start blocking."
        case .unknown: return "iOS hasn’t reported whether SpamBlock is switched on."
        }
    }

    // MARK: - Rules

    private var blockListSection: some View {
        Section {
            if list.rules.isEmpty {
                Text(list.isEditable
                     ? "No area codes yet. Tap + to add one."
                     : "No area codes yet. Add them to Shared/BlockedAreaCodes.swift.")
                    .foregroundStyle(.secondary)
            } else if list.isEditable {
                ForEach(list.rules) { rule in
                    ruleRow(rule)
                }
                .onDelete { list.delete(at: $0) }
            } else {
                ForEach(list.rules) { rule in
                    ruleDetail(rule)
                }
            }
        } header: {
            Text("Blocked")
        } footer: {
            if !list.rules.isEmpty {
                totalFooter
            }
        }
    }

    private func ruleRow(_ rule: BlockRule) -> some View {
        Toggle(isOn: Binding(
            get: { rule.isEnabled },
            set: { list.setEnabled($0, for: rule) }
        )) {
            ruleDetail(rule)
        }
    }

    private func ruleDetail(_ rule: BlockRule) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PrefixValidator.formatted(rule.prefix))
                .font(.body.monospacedDigit())
            Text(PrefixValidator.scopeDescription(rule.prefix))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !rule.note.isEmpty {
                Text(rule.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(NumberPlan.entryCount(for: rule.prefix).formatted()) numbers")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Shown instead of the editing affordances when the list is compiled in.
    private var compiledInListSection: some View {
        Section {
            Label {
                Text("This list is built into the app. Editing it here isn’t possible on a free Apple ID — change Shared/BlockedAreaCodes.swift, push, and reinstall the new build.")
                    .font(.callout)
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }

    private var totalFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(list.entryCount.formatted()) numbers in total.")
            switch list.budgetLevel {
            case .comfortable:
                EmptyView()
            case .risky:
                Text("That’s a lot for iOS to hold. It may load slowly, or refuse to load on an older iPhone.")
                    .foregroundStyle(.orange)
            case .overBudget:
                Text("This is more than iOS is likely to accept. Remove an area code, or narrow one to the exchanges that actually call you — tap + and enter six digits instead of three.")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Shared bits

    private func messageRow(text: String, kind: CallDirectoryController.Message.Kind) -> some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(kind == .success ? Color.green : Color.red)
        }
    }

    private func applyChanges() {
        directory.reload {
            list.markApplied()
        }
    }
}

#Preview {
    ContentView()
}
