import HerdrKit

/// A Shepherd feature. Every feature is one module in `Sources/ShepherdModules/<Name>/`.
/// The full contract (menu bar contribution, panel section, notch content, actions)
/// lands in milestone 1; see docs/PRD.md.
@MainActor
public protocol ShepherdModule: AnyObject {
    /// Stable id used in config.json to enable, disable and order modules.
    static var id: String { get }
}
