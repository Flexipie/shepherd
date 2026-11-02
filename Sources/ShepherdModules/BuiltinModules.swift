import ShepherdCore

/// The built-in modules, in default order. A new module adds itself here and nowhere else.
@MainActor
public enum BuiltinModules {
    public static let all: [any ShepherdModule.Type] = [
        StatusModule.self,
        NotchModule.self,
        DemoModule.self,
        SourcesModule.self,
        QueueModule.self,
        ProjectsModule.self,
        NotificationsModule.self,
        ContextModule.self,
        PluginsModule.self,
    ]

    /// Ids of modules that were removed, so an old config naming them still loads quietly.
    public static let retired: Set<String> = ["usage", "system"]
}
