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
        let builtIn = BlockedAreaCodes.prefixes.map { BlockRule(prefix: $0) }
        if let saved = store.loadSaved() {
            rules = saved
        } else {
            // With no App Group there is nowhere to write rules that the
            // extension could read, so the compiled-in list is shown instead —
            // the same list the extension is using, just not editable here.
            // With one but nothing saved yet, the extensions are using the
            // compiled-in list too, so that's where editing starts; saving it
            // now keeps the app and the extensions reading the same thing.
            rules = builtIn
            if store.isAvailable {
                try? store.save(builtIn)
            }
        }
        lastAppliedSignature = UserDefaults.standard.string(forKey: Self.appliedSignatureKey)
    }

    var plan: NumberPlan { NumberPlan(rules: rules) }
    var entryCount: Int { plan.entryCount }

    /// How many parts the list is split into — as many as this build ships
    /// extensions, recorded in each of them.
    var partCount: Int {
        AppConfiguration.embeddedExtensions.first?.slice.count ?? 1
    }

    /// The largest part, which is the number that has to fit in one extension.
    var largestPart: Int {
        NumberPlan.largestPart(of: plan.prefixes, count: partCount)
    }

    /// Whether `prefix` still fits once added: every part within the size one
    /// extension is known to load. Checked before adding rather than left to
    /// iOS, which rejects an oversized part outright and says only that the
    /// data was invalid.
    func hasRoom(for prefix: String) -> Bool {
        NumberPlan.largestPart(of: plan.prefixes + [prefix], count: partCount) <= EntryBudget.comfortable
    }

    /// How many whole area codes the parts can hold, for explaining the limit.
    var areaCodeCapacity: Int {
        partCount * EntryBudget.comfortable / NumberPlan.entryCount(for: "415")
    }

    var budgetLevel: EntryBudget.Level { EntryBudget.level(for: largestPart) }

    /// After a reload that started at `start`, whether every part read the
    /// list saved here, going by the reports they leave in the shared
    /// container. Nil when there's no container to check through.
    func partsReadCurrentList(since start: Date) -> Bool? {
        guard store.isAvailable else { return nil }
        let expected = plan.prefixes
        // A little slack: the report is stamped by another process.
        let earliest = start.addingTimeInterval(-5)
        return (1...max(partCount, 1)).allSatisfy { part in
            guard let report = store.loadReport(part: part) else { return false }
            return report.prefixes == expected && report.loadedAt >= earliest
        }
    }
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
    ///
    /// The part count is included because a build with more parts splits the
    /// same list differently: the parts already on the phone hold the old
    /// split until they reload, the new ones duplicate part of it, and nothing
    /// would say so.
    private var signature: String {
        "\(partCount) parts: " + plan.prefixes.joined(separator: ",")
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
