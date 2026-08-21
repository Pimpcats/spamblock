import SwiftUI

/// Owns the rule list and keeps the shared container in step with it.
@MainActor
final class BlockListViewModel: ObservableObject {

    @Published private(set) var rules: [BlockRule] = []
    @Published private(set) var saveError: String?
    @Published private var lastAppliedSignature: String?

    private let store = RuleStore.shared
    private static let appliedSignatureKey = "lastAppliedPlanSignature"

    init() {
        // With no App Group there is nowhere to write rules that the extension
        // could read, so the compiled-in list is shown instead — the same list
        // the extension is using, just not editable from here.
        rules = store.isAvailable
            ? store.load()
            : BlockedAreaCodes.prefixes.map { BlockRule(prefix: $0) }
        lastAppliedSignature = UserDefaults.standard.string(forKey: Self.appliedSignatureKey)
    }

    var plan: NumberPlan { NumberPlan(rules: rules) }
    var entryCount: Int { plan.entryCount }
    var budgetLevel: EntryBudget.Level { EntryBudget.level(for: entryCount) }
    var existingPrefixes: Set<String> { Set(rules.map(\.prefix)) }

    /// Whether rules edited here can reach the extension at all.
    ///
    /// `false` on a free Apple ID: the list is compiled into the app, so it can
    /// be shown but not changed.
    var isEditable: Bool { store.isAvailable }

    /// Whether the saved rules differ from what iOS is actually enforcing.
    ///
    /// Editing a rule only writes a file; nothing changes on the phone until
    /// the extension is reloaded, and that gap is invisible without saying so.
    var hasUnappliedChanges: Bool {
        (lastAppliedSignature ?? "") != signature
    }

    /// Identifies the *effective* block list, so toggling a rule off and back
    /// on, or adding one already covered by a broader rule, doesn't ask for a
    /// pointless multi-million-entry reload.
    private var signature: String {
        plan.prefixes.joined(separator: ",")
    }

    func add(prefix: String, note: String) {
        rules.append(BlockRule(prefix: prefix, note: note))
        rules.sort { $0.prefix < $1.prefix }
        persist()
    }

    func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for rule: BlockRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled = isEnabled
        persist()
    }

    func markApplied() {
        let applied = signature
        UserDefaults.standard.set(applied, forKey: Self.appliedSignatureKey)
        lastAppliedSignature = applied
    }

    private func persist() {
        do {
            try store.save(rules)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
