import Observation

/// The enabled modules, in config order. Built from `config.modules` (every available module in
/// default order when the key is absent) and rebuilt when that list changes, so a config save
/// adds, removes and reorders modules live. A module that stays enabled keeps its instance and
/// its state. Surfaces read `modules` inside observation tracking.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var modules: [any ShepherdModule] = []

    @ObservationIgnored private let available: [any ShepherdModule.Type]
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var enabled: [String]?

    public init(available: [any ShepherdModule.Type], context: ModuleContext) {
        self.available = available
        self.context = context
        update()
    }

    private func update() {
        let ids = withObservationTracking {
            context.config.config.modules
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        guard modules.isEmpty || ids != enabled else { return }
        enabled = ids
        build(ids)
    }

    private func build(_ ids: [String]?) {
        let types = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = ids ?? available.map { $0.id }
        let unknown = wanted.filter { types[$0] == nil }
        context.config.report(unknown.isEmpty ? nil : "config: unknown module \(unknown.map { "\"\($0)\"" }.joined(separator: ", "))",
                              for: "modules")
        let existing = Dictionary(modules.map { (type(of: $0).id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        modules = wanted.compactMap { id in
            guard seen.insert(id).inserted, let type = types[id] else { return nil }
            return existing[id] ?? type.init(context: context)
        }
    }
}
