import Darwin
import Foundation

/// Thin wrappers over the BSD socket calls Shepherd needs, with errno mapped to `HerdrError`.
package enum UnixSocket {
    /// `sun_path` is 104 bytes including the terminating NUL.
    package static let maxPathLength = 103

    package static func address(for path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count <= maxPathLength else {
            throw HerdrError.socketPathTooLong(path)
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    /// A blocking stream socket with `SO_NOSIGPIPE` set, so a closed peer is an error, not a signal.
    package static func makeSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.io(errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// Connects to a listening socket. Blocking; call it off the main actor.
    package static func connect(path: String) throws -> Int32 {
        var addr = try address(for: path)
        let fd = try makeSocket()
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            switch code {
            case ENOENT, ECONNREFUSED: throw HerdrError.notRunning
            case EACCES, EPERM: throw HerdrError.permissionDenied
            default: throw HerdrError.io(code)
            }
        }
        return fd
    }

    package static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    /// Sets send and receive timeouts on a blocking socket.
    package static func setTimeout(_ fd: Int32, _ timeout: Duration) {
        let (seconds, attoseconds) = timeout.components
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
    }

    /// Writes every byte on a blocking socket.
    package static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw errno == EAGAIN ? HerdrError.timeout : HerdrError.disconnected
                }
                remaining -= written
                pointer += written
            }
        }
    }

    /// Reads from a blocking socket until one full line arrives.
    package static func readLine(_ fd: Int32) throws -> Data {
        var buffer = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                if let line = try buffer.append(chunk[0..<count]).first { return line }
            } else if count == 0 {
                throw HerdrError.disconnected
            } else if errno == EINTR {
                continue
            } else {
                throw errno == EAGAIN ? HerdrError.timeout : HerdrError.io(errno)
            }
        }
    }
}
