import Dispatch
import Foundation
import TmuxKit

/// Calls back when the tmux socket folder's listing changes, without polling: a vnode watch, debounced.
/// The folder is watched when it exists and its parent otherwise, so a first server is noticed. The
/// listing is compared before calling back, so unrelated activity in the parent costs one listing.
/// Follows `ReportWatcher`, which does the same for a folder Shepherd owns.
final class TmuxSocketWatcher: @unchecked Sendable {
    let directory: URL
    private let handler: @Sendable () -> Void
    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "shepherd.tmux-watcher", qos: .utility)
    private var source: (any DispatchSourceFileSystemObject)?
    private var pending: DispatchWorkItem?
    private var listing: [String] = []
    private var running = false

    init(directory: URL, handler: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.handler = handler
    }

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.listing = TmuxSockets.sockets(in: self.directory)
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
        queue.asyncAfter(deadline: .now() + .milliseconds(50), execute: work)
    }

    private func fire() {
        guard running else { return }
        let now = TmuxSockets.sockets(in: directory)
        rewatch()
        guard now != listing else { return }
        listing = now
        handler()
    }

    private func rewatch() {
        cancelSource()
        let watched = FileManager.default.fileExists(atPath: directory.path) ? directory : directory.deletingLastPathComponent()
        let fd = open(watched.path, O_EVTONLY)
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
