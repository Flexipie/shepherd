import Foundation
import ShepherdCore

/// Reads plan usage from OpenUsage's local API (`GET /v1/limits`, schema `openusage.limits.v1`),
/// served by the OpenUsage app on loopback. Shepherd holds no credentials and talks to nothing
/// else: OpenUsage does the fetching, Shepherd only reads what it already has.
///
/// `SHEPHERD_OPENUSAGE_URL` points a dev run at another loopback address. Anything that is not
/// loopback is ignored.
@MainActor
public final class OpenUsageReader: UsageReader {
    public nonisolated static let defaultBaseURL = URL(string: "http://127.0.0.1:6736")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL? = nil) {
        let override = ProcessInfo.processInfo.environment["SHEPHERD_OPENUSAGE_URL"].flatMap(URL.init(string:))
        let wanted = baseURL ?? override ?? Self.defaultBaseURL
        self.baseURL = Self.isLoopback(wanted) ? wanted : Self.defaultBaseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func read() async throws -> UsageReport {
        let url = baseURL.appending(path: "v1/limits")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost: throw OpenUsageError.notRunning
            case .timedOut: throw OpenUsageError.timedOut
            default: throw OpenUsageError.unreadable(error.localizedDescription)
            }
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OpenUsageError.status(http.statusCode)
        }
        return try OpenUsageLimits.report(from: data)
    }

    nonisolated static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host() ?? "")
    }
}

public enum OpenUsageError: Error, LocalizedError, Equatable {
    case notRunning
    case timedOut
    case status(Int)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            "OpenUsage is not running. Shepherd reads Claude and Codex usage from it: github.com/robinebers/openusage"
        case .timedOut: "OpenUsage did not answer in time."
        case .status(let code): "OpenUsage answered with HTTP \(code)."
        case .unreadable(let reason): "Could not read OpenUsage: \(reason)"
        }
    }
}
