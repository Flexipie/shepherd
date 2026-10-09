import Foundation
import Observation

/// The current config, reloaded when the file changes. A file that cannot be read at all keeps
/// the last good config and says why; smaller problems are listed while the rest applies. Other
/// parts of the app (the hotkey) report their own config problems here too, so the panel shows
/// them in one place.
@MainActor
@Observable
public final class ConfigStore {
    public private(set) var config: ShepherdConfig
    /// Problems from reading the file, then any reported by the app, for the panel footer.
    public var problems: [String] { fileProblems + reported.keys.sorted().compactMap { reported[$0] } }

    public let url: URL
    private var fileProblems: [String] = []
    private var reported: [String: String] = [:]
    @ObservationIgnored private var watcher: FileWatcher?

    /// Reads the file now; with `watch`, keeps reading it as it changes.
    public init(url: URL = ShepherdConfig.defaultURL(), watch: Bool = true) {
        self.url = url
        config = .defaults
        let data = try? Data(contentsOf: url)
        apply(data)
        guard watch else { return }
        let watcher = FileWatcher(url: url) { [weak self] data in
            Task { @MainActor in self?.apply(data) }
        }
        self.watcher = watcher
        watcher.start(known: data)
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
    }

    /// Sets or clears (nil) a problem the app found with part of the config, such as a hotkey that
    /// cannot be registered.
    public func report(_ problem: String?, for key: String) {
        if reported[key] != problem { reported[key] = problem }
    }

    func apply(_ data: Data?) {
        guard let data else {
            set(.defaults, problems: [])
            return
        }
        do {
            let (config, problems) = try ShepherdConfig.read(data)
            set(config, problems: problems)
        } catch {
            // Keep the last good config; say why the new one was not used.
            set(config, problems: [error.message + " (using the last good config)"])
        }
    }

    private func set(_ new: ShepherdConfig, problems: [String]) {
        if config != new { config = new }
        if fileProblems != problems { fileProblems = problems }
    }
}
