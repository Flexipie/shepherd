import Foundation

/// Where the herdr socket lives, following herdr's own resolution order:
/// `HERDR_SOCKET_PATH`, then `HERDR_SESSION=<name>`, then the default session.
public enum HerdrSocket {
    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let explicit = environment["HERDR_SOCKET_PATH"], !explicit.isEmpty {
            return explicit
        }
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/herdr")
        if let session = environment["HERDR_SESSION"], !session.isEmpty {
            return configDir.appendingPathComponent("sessions/\(session)/herdr.sock").path
        }
        return configDir.appendingPathComponent("herdr.sock").path
    }
}
