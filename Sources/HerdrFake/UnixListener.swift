import Darwin
import Dispatch
import Foundation
import HerdrKit

/// A listening Unix socket that hands each accepted connection's fd to `onAccept`.
final class UnixListener: Sendable {
    private let source: any DispatchSourceRead
    let path: String

    init(path: String, onAccept: @escaping @Sendable (Int32) -> Void) throws {
        unlink(path)
        var addr = try UnixSocket.address(for: path)
        let fd = try UnixSocket.makeSocket()
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 64) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw HerdrError.io(code)
        }
        UnixSocket.setNonBlocking(fd)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "dev.shepherd.fake.listener"))
        source.setEventHandler {
            while true {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else { return }
                // Accepted sockets inherit O_NONBLOCK on macOS; requests are handled as blocking.
                let flags = fcntl(client, F_GETFL)
                _ = fcntl(client, F_SETFL, flags & ~O_NONBLOCK)
                var on: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                onAccept(client)
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        self.path = path
        source.resume()
    }

    /// Stops listening and removes the socket file, as herdr does when it quits.
    func close() {
        // Unlink now, not in the cancel handler: a restart may bind the same path right away.
        unlink(path)
        source.cancel()
    }
}
