import Foundation
import Synchronization

/// One request line: `{"id","method","params"}`.
package struct RequestEnvelope<Params: Encodable & Sendable>: Encodable, Sendable {
    package let id: String
    package let method: String
    package let params: Params

    package init(id: String = RequestID.next(), method: String, params: Params) {
        self.id = id
        self.method = method
        self.params = params
    }

    package func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}

/// Empty `{}` params.
public struct NoParams: Encodable, Sendable {
    public init() {}
}

package enum RequestID {
    private static let counter = Atomic<UInt64>(0)

    package static func next() -> String {
        "shepherd-\(counter.add(1, ordering: .relaxed).newValue)"
    }
}

/// A line from herdr, classified: a response carries an `id`, a pushed event does not.
package enum IncomingLine: Sendable {
    /// A success response. `line` is kept so the caller can decode `result` as its own type.
    case result(id: String, line: Data)
    case error(id: String, code: ServerErrorCode, message: String)
    case event(HerdrEvent)

    package init(_ line: Data) throws {
        let probe: Probe
        do {
            probe = try JSONDecoder().decode(Probe.self, from: line)
        } catch {
            throw HerdrError.unexpectedResponse("not a JSON object")
        }
        if let id = probe.id {
            if let error = probe.error {
                self = .error(id: id, code: error.code, message: error.message ?? "")
            } else {
                self = .result(id: id, line: line)
            }
        } else if probe.event != nil {
            self = .event(try JSONDecoder().decode(HerdrEvent.self, from: line))
        } else {
            throw HerdrError.unexpectedResponse("line has neither id nor event")
        }
    }

    private struct Probe: Decodable {
        let id: String?
        let error: ErrorBody?
        let event: String?
    }

    private struct ErrorBody: Decodable {
        let code: ServerErrorCode
        let message: String?
    }
}

/// Decodes the `result` of a success response.
package struct ResultEnvelope<Result: Decodable>: Decodable {
    package let result: Result
}

/// Accepts any `result`, for calls where only success matters.
public struct IgnoredResult: Decodable, Sendable {
    public init(from decoder: any Decoder) throws {}
}
