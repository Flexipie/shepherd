import Dispatch
import Foundation

/// Calls back with a file's contents whenever they change, without polling. It watches the
/// directory, so saves that write a temporary file and rename it over the original are seen, and
/// the file itself, so in-place writes are too. If the directory does not exist yet, it watches
/// the nearest existing ancestor until it does. Events are debounced, and the callback runs only
/// when the bytes differ from what it last delivered (nil for a missing file).
public final class FileWatcher: @unchecked Sendable {
    public let url: URL
    private let debounce: DispatchTimeInterval
    private let handler: @Sendable (Data?) -> Void
    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "shepherd.file-watcher", qos: .utility)
    private var sources: [any DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var last: Data?
    private var running = false

    public init(url: URL, debounce: DispatchTimeInterval = .milliseconds(200), handler: @escaping @Sendable (Data?) -> Void) {
        self.url = url
        self.debounce = debounce
        self.handler = handler
    }

    /// Starts watching. `known` is the content the caller already has, so it is not delivered again.
    public func start(known: Data?) {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.last = known
            self.rewatch()
            // The file may have changed between the caller's read and the watch starting.
            self.check()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            pending?.cancel()
            pending = nil
            cancelSources()
        }
    }

    deinit {
        for source in sources { source.cancel() }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func check() {
        guard running else { return }
        // A rename or delete invalidates the watched descriptors, and a created directory or file
        // can now be watched directly, so re-establish the watches every time.
        rewatch()
        let data = try? Data(contentsOf: url)
        guard data != last else { return }
        last = data
        handler(data)
    }

    private func rewatch() {
        cancelSources()
        var directory = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.path), directory.pathComponents.count > 1 {
            directory = directory.deletingLastPathComponent()
        }
        watch(directory.path, events: [.write, .rename, .delete, .link])
        watch(url.path, events: [.write, .extend, .delete, .rename, .attrib])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
    }

    private func cancelSources() {
        for source in sources { source.cancel() }
        sources.removeAll()
    }
}
