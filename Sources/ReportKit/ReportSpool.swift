import CryptoKit
import Darwin
import Foundation

/// The folder of report files: one `<sha256 of the agent key>.json` per agent. Writes go to a
/// hidden temporary file that is renamed into place, so a reader never sees half a report.
public struct ReportSpool: Sendable {
    /// What a read found: the reports it could use, and one line per file it skipped.
    public struct Contents: Sendable, Equatable {
        public let reports: [ReportFile]
        public let problems: [String]
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `SHEPHERD_SPOOL_DIR` when set, else the app's folder under Application Support.
    public static func directory(environment: [String: String]) -> URL {
        if let path = environment["SHEPHERD_SPOOL_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL.applicationSupportDirectory.appending(path: "Shepherd/reports")
    }

    /// The file for an agent key.
    public func url(for agent: String) -> URL {
        let digest = SHA256.hash(data: Data(agent.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json")
    }

    /// Writes the report, replacing the agent's earlier one in a single rename.
    public func write(_ report: ReportFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try report.encoded()
        let target = url(for: report.agent)
        let temporary = directory.appending(path: ".\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        guard rename(temporary.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    /// Removes the agent's report. A missing file is not an error.
    public func remove(agent: String) throws {
        let target = url(for: agent)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Every readable report, in file name order. Creates the folder if missing. A file that
    /// cannot be read or decoded is skipped and named in `problems`; nothing else fails the read.
    public func read() throws -> Contents {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var reports: [ReportFile] = []
        var problems: [String] = []
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let file = directory.appending(path: name)
            guard let data = try? Data(contentsOf: file) else {
                // Removed between listing and reading: nothing to report.
                if FileManager.default.fileExists(atPath: file.path) { problems.append("\(name) cannot be read") }
                continue
            }
            do {
                reports.append(try ReportFile.decode(data))
            } catch {
                problems.append("\(name): \(error)")
            }
        }
        return Contents(reports: reports, problems: problems)
    }
}
