import Darwin
import Dispatch
import Foundation

/// A long-lived socket read with a GCD read source: the kernel wakes it only when bytes arrive,
/// so an idle connection costs nothing. Lines come out of `lines`; the stream ends with
/// `HerdrError.disconnected` on EOF. Each connection has its own serial queue; the fd is closed
/// only in the source's cancel handler, and writes run on the same queue, so a write can never
/// reach a closed or reused fd.
package final class LineConnection: Sendable {
    package let lines: AsyncThrowingStream<Data, any Error>
    private let source: any DispatchSourceRead
    private let queue: DispatchQueue
    private let state: ReadState
    private let fd: Int32

    /// Takes ownership of `fd`.
    package init(fd: Int32, maxLineLength: Int = LineBuffer.defaultMaxLineLength) {
        UnixSocket.setNonBlocking(fd)
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let queue = DispatchQueue(label: "dev.shepherd.herdr.connection", qos: .utility)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let state = ReadState(maxLineLength: maxLineLength)

        source.setEventHandler {
            if let error = state.drain(fd: fd, into: continuation) {
                continuation.finish(throwing: error)
                source.cancel()
            }
        }
        source.setCancelHandler {
            state.isClosed = true
            Darwin.close(fd)
            continuation.finish(throwing: HerdrError.disconnected)
        }
        continuation.onTermination = { _ in source.cancel() }

        self.lines = stream
        self.source = source
        self.queue = queue
        self.state = state
        self.fd = fd
        source.resume()
    }

    /// Writes bytes, waiting while the peer's buffer is full. Never call it from `lines`'
    /// producer queue; callers are tasks or other queues.
    package func write(_ data: Data) throws {
        try queue.sync {
            guard !state.isClosed else { throw HerdrError.disconnected }
            try UnixSocket.writeAll(fd, data)
        }
    }

    /// Closes the connection. Safe to call more than once.
    package func close() {
        source.cancel()
    }
}

/// Read buffers for one connection. Only touched on the connection's serial queue, hence the
/// unchecked conformance.
private final class ReadState: @unchecked Sendable {
    var isClosed = false
    private var buffer: LineBuffer
    private var chunk = [UInt8](repeating: 0, count: 64 * 1024)

    init(maxLineLength: Int) {
        buffer = LineBuffer(maxLineLength: maxLineLength)
    }

    /// Reads until the socket would block. Returns the error that ends the stream, if any.
    func drain(fd: Int32, into continuation: AsyncThrowingStream<Data, any Error>.Continuation) -> (any Error)? {
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                do {
                    for line in try buffer.append(chunk[0..<count]) { continuation.yield(line) }
                } catch {
                    return error
                }
            } else if count == 0 {
                return HerdrError.disconnected
            } else {
                switch errno {
                case EINTR: continue
                case EAGAIN: return nil
                default: return HerdrError.io(errno)
                }
            }
        }
    }
}
