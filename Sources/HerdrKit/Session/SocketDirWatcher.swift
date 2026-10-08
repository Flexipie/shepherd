import Darwin
import Dispatch
import Foundation

/// Watches the folder holding herdr's socket while herdr is down, so Shepherd reconnects as soon
/// as the socket appears instead of waiting out its backoff. Runs only while disconnected.
final class SocketDirWatcher: Sendable {
    private let source: (any DispatchSourceFileSystemObject)?

    init(socketPath: String, onChange: @escaping @Sendable () -> Void) {
        let directory = (socketPath as NSString).deletingLastPathComponent
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "dev.shepherd.herdr.socket-dir", qos: .utility))
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.source = source
    }

    func cancel() {
        source?.cancel()
    }
}
