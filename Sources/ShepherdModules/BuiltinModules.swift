import ShepherdCore

/// The built-in modules, in default order. A new module adds itself here and nowhere else.
@MainActor
public enum BuiltinModules {
    public static let all: [any ShepherdModule.Type] = []
}
