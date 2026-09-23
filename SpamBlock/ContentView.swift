import SwiftUI
import UIKit

struct ContentView: View {

    @StateObject private var list = BlockListViewModel()
    @StateObject private var directory = CallDirectoryController()
    @StateObject private var contacts = ContactAccessController()
    @State private var isAddingRule = false

    var body: some View {
        NavigationStack {
            List {
                if !AppConfiguration.isExtensionEmbedded { missingExtensionSection }
                if !list.isEditable { compiledInListSection }
                statusSection
                contactsSection
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
            .onAppear {
                directory.refreshStatus()
                contacts.refresh(against: list.plan)
            }
            // Turning the extension on happens in Settings, outside the app, so
            // the switch is re-read every time the app comes back to the front.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                directory.refreshStatus()
                contacts.refresh(against: list.plan)
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

    // MARK: - Missing extension

    /// Shown when the app shipped without its extension.
    ///
    /// This is the failure that looks most like success: the app installs,
    /// opens, lists the area codes and offers every button, while iOS has
    /// nothing to block with and never says so. Worth stating at the top, in
    /// terms of the thing that caused it.
    private var missingExtensionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("No call blocking extension").font(.headline)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
                Text("This copy of SpamBlock was installed without its extension, which is the part that actually blocks calls. Nothing below has any effect, and SpamBlock won’t appear under Call Blocking & Identification.")
                    .font(.callout)
                Text("Sideload the .ipa again with “Remove app extensions” switched off.")
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Contacts

    /// Contacts permission is load-bearing, not a nicety: without it the
    /// extension has nothing to exempt and the area code is blocked outright,
    /// including people you know. That has to be visible.
    private var contactsExemptSummary: String {
        switch contacts.exemptedCount {
        case 0: return "No one in your contacts is in a blocked area code."
        case 1: return "1 contact in a blocked area code will still ring."
        default: return "\(contacts.exemptedCount) contacts in a blocked area code will still ring."
        }
    }

    private var contactsSection: some View {
        Section {
            switch contacts.status {
            case .granted:
                Label {
                    Text(contactsExemptSummary)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.green)
                }
            case .notDetermined:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Right now every number in a blocked area code is rejected, including people in your contacts.")
                        .font(.callout)
                    Button("Allow contacts access") {
                        contacts.requestAccess(against: list.plan)
                    }
                }
            case .denied:
                Label {
                    Text("Contacts access is off, so everyone in a blocked area code is rejected — contacts included. Turn it on in Settings › SpamBlock › Contacts.")
                        .font(.callout)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Contacts")
        } footer: {
            Text("Changes to your contacts reach the block list the next time it loads, not immediately. Tap Update block list after adding someone in a blocked area code.")
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
