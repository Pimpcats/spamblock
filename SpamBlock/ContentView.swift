import Contacts
import SwiftUI
import UIKit

struct ContentView: View {

    @StateObject private var list = BlockListViewModel()
    @StateObject private var directory = CallDirectoryController()
    @StateObject private var contacts = ContactAccessController()
    @StateObject private var knownSpam = KnownSpamController()
    @State private var isAddingRule = false

    var body: some View {
        NavigationStack {
            List {
                if !AppConfiguration.isExtensionEmbedded {
                    missingExtensionSection
                } else if !AppConfiguration.missingPartNumbers.isEmpty {
                    missingPartsSection
                }
                if !list.isEditable { compiledInListSection }
                statusSection
                contactsSection
                blockListSection
                knownSpamSection
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
                knownSpam.refresh()
            }
            // Turning the extension on happens in Settings, outside the app, so
            // the switch is re-read every time the app comes back to the front.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                directory.refreshStatus()
                contacts.refresh(against: list.plan)
                knownSpam.refresh()
            }
            // Contacts edited while SpamBlock is open.
            .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange)) { _ in
                contacts.refresh(against: list.plan)
            }
            // Each fresh reading of the address book, and each change to the
            // parts' switches, is a chance to catch the block list up with
            // contacts added since it last loaded.
            .onChange(of: contacts.planFingerprint) { _ in
                applyContactChangesToParts()
            }
            .onChange(of: directory.status) { _ in
                applyContactChangesToParts()
            }
            .onChange(of: contacts.allFingerprint) { fingerprint in
                if let fingerprint {
                    knownSpam.contactsDidChange(fingerprint: fingerprint)
                }
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

            // Each part has its own switch in Settings, and a part left off is
            // a gap in the list, so they're listed rather than summarised.
            if directory.parts.count > 1 {
                ForEach(directory.parts, id: \.slice.number) { part in
                    partRow(part.slice)
                }
            }

            if directory.status != .enabled {
                Button("Open call blocking settings") { directory.openSettings() }
            }

            Button(action: applyChanges) {
                HStack {
                    Text(reloadButtonTitle)
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
            Text(directory.parts.count > 1
                 ? "Every SpamBlock part has to be switched on under Settings › Apps › Phone › Call Blocking & Identification. Each carries a different slice of the list, so one left off is a gap."
                 : "iOS only blocks calls once SpamBlock is switched on under Settings › Apps › Phone › Call Blocking & Identification, and only after the list has been loaded.")
        }
    }

    private var reloadButtonTitle: String {
        if let part = directory.reloadingPart, directory.parts.count > 1 {
            return "Loading part \(part) of \(directory.parts.count)…"
        }
        return list.hasUnappliedChanges ? "Update block list" : "Reload block list"
    }

    private func partRow(_ slice: ExtensionSlice) -> some View {
        HStack {
            Text("SpamBlock — \(slice.number) of \(slice.count)")
            Spacer()
            switchLabel(directory.status(ofPart: slice.number))
        }
        .font(.callout)
    }

    /// An extension's switch in Settings, as last reported by iOS.
    @ViewBuilder
    private func switchLabel(_ state: CallDirectoryController.Status) -> some View {
        switch state {
        case .enabled:
            Label("On", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disabled:
            Label("Off", systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        case .unknown:
            Text("—").foregroundStyle(.secondary)
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

    // MARK: - Known spam

    /// The FTC list is a separate extension with its own switch, loaded from
    /// a download rather than from the area codes, so it gets its own status
    /// and its own update button rather than riding on the ones above.
    private var knownSpamSection: some View {
        Section {
            if !knownSpam.isInstalled {
                Label {
                    Text("The Known spam extension wasn’t installed. Sideload again and keep every extension, choosing “Register App ID for Each Extension”.")
                        .font(.callout)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } else {
                HStack {
                    Text("SpamBlock — Known spam")
                    Spacer()
                    switchLabel(knownSpam.status)
                }
                .font(.callout)

                if let info = knownSpam.info {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.count.formatted()) numbers")
                            .font(.body.monospacedDigit())
                        Text("Reported to the FTC at least \(info.minReports) times in the last \(info.windowDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let loadedAt = knownSpam.loadedAt {
                    (Text("Loaded on this iPhone ") + Text(loadedAt, format: .relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if knownSpam.status == .disabled {
                    Button("Open call blocking settings") { directory.openSettings() }
                }

                Button {
                    knownSpam.reload()
                } label: {
                    HStack {
                        Text(knownSpam.isReloading ? "Updating…" : "Update now")
                        Spacer()
                        if knownSpam.isReloading {
                            ProgressView()
                        }
                    }
                }
                .disabled(knownSpam.isReloading || knownSpam.status == .disabled)

                if let message = knownSpam.message {
                    messageRow(text: message.text, kind: message.kind)
                }
            }
        } header: {
            Text("Known spam")
        } footer: {
            Text("Numbers people have reported to the FTC’s Do Not Call registry, wherever they’re from. The list is rebuilt daily, and SpamBlock fetches it about once a day. People in your contacts still ring through.")
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

    /// Shown when a sideloader kept some parts and dropped others.
    private var missingPartsSection: some View {
        let missing = AppConfiguration.missingPartNumbers
        let total = AppConfiguration.embeddedExtensions.first?.slice.count ?? 0
        let names = missing.map { "\($0) of \(total)" }.joined(separator: ", ")
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(missing.count == 1 ? "A part is missing" : "\(missing.count) parts are missing")
                        .font(.headline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text("SpamBlock \(names) wasn’t installed, so that slice of the list isn’t blocked.")
                    .font(.callout)
                Text("Sideload again and keep every extension, choosing “Register App ID for Each Extension”.")
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
                Button(action: updateContacts) {
                    HStack {
                        Text(isUpdatingContacts ? "Updating…" : "Update contacts now")
                        Spacer()
                        if isUpdatingContacts {
                            ProgressView()
                        }
                    }
                }
                .disabled(isUpdatingContacts)
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
            Text(contacts.status == .granted
                 ? "When your contacts change, SpamBlock reloads the block list by itself the next time it's open, so people you add ring through. Update contacts now does it straight away."
                 : "Without contacts access, SpamBlock can't tell who you know.")
        }
    }

    private var isUpdatingContacts: Bool {
        directory.isReloading || knownSpam.isReloading
    }

    /// Reloads everything that skips contacts, so the address book as it is
    /// now takes effect: every area-code part, and Known spam.
    private func updateContacts() {
        reloadParts()
        knownSpam.reload()
    }

    /// Reloads the area-code parts when contacts in a blocked area code have
    /// changed since they last loaded. Only with every part switched on: a
    /// part that's off can't load, and each reload takes a while.
    private func applyContactChangesToParts() {
        guard let current = contacts.planFingerprint else { return }
        guard let applied = AppliedContacts.parts else {
            // The first reading since this existed: treat what's loaded as
            // current rather than reloading millions of numbers on a guess.
            AppliedContacts.parts = current
            return
        }
        guard applied != current, directory.status == .enabled, !directory.isReloading else { return }
        reloadParts()
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
            Text(list.partCount > 1
                 ? "\(list.entryCount.formatted()) numbers in total, split into \(list.partCount) parts of up to \(list.largestPart.formatted()) each."
                 : "\(list.entryCount.formatted()) numbers in total.")
            switch list.budgetLevel {
            case .comfortable:
                EmptyView()
            case .risky:
                Text("That’s more per part than has been seen to load. It may be rejected.")
                    .foregroundStyle(.orange)
            case .overBudget:
                Text("That’s more per part than iOS has accepted. Expect it to be rejected when switched on.")
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
        reloadParts()
    }

    /// Every reload of the parts also re-reads contacts, so each successful
    /// one records which contacts it included.
    private func reloadParts() {
        let contactsNow = contacts.planFingerprint
        directory.reload {
            list.markApplied()
            if let contactsNow {
                AppliedContacts.parts = contactsNow
            }
        }
    }
}

#Preview {
    ContentView()
}
