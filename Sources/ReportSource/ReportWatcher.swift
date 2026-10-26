import Dispatch
import Foundation

/// Calls back whenever a folder's contents change, without polling: a vnode watch on the folder,
/// debounced, and watched again after each event so a removed or renamed folder is picked up. The
/// folder is created if missing. Follows `FileWatcher`, which does the same for one file.
final class ReportWatcher: @unchecked Sendable {
    let directory: URL
    private let debounce: DispatchTimeInterval
    private let handler: @Sendable () -> Void
    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "shepherd.report-watcher", qos: .utility)
    private var source: (any DispatchSourceFileSystemObject)?
    private var pending: DispatchWorkItem?
    private var running = false

    init(directory: URL, debounce: DispatchTimeInterval = .milliseconds(50), handler: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.handler = handler
    }

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.ensureDirectory()
            self.rewatch()
        }
    }

    func stop() {
        queue.sync {
            running = false
            pending?.cancel()
            pending = nil
            cancelSource()
        }
    }

    deinit {
        source?.cancel()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func fire() {
        guard running else { return }
        ensureDirectory()
        rewatch()
        handler()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func rewatch() {
        cancelSource()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link],
                                                               queue: queue)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func cancelSource() {
        source?.cancel()
        source = nil
    }
}
