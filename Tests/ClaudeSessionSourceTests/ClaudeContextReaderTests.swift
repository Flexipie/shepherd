import Foundation
import Testing
@testable import ClaudeSessionSource
@testable import ShepherdCore

@Suite struct ClaudeSessionFileTests {
    static let fixture = Bundle.module.url(forResource: "Fixtures/session", withExtension: "jsonl")!

    @Test func folderNameEscapesEveryNonAlphanumeric() {
        #expect(ClaudeSessionFile.folderName("/Users/jane/.config/my_app v2") == "-Users-jane--config-my-app-v2")
        #expect(ClaudeSessionFile.folderName("/tmp/café") == "-tmp-caf-")
    }

    @Test func onlyPlainSessionIDsAreUsed() {
        #expect(ClaudeSessionFile.isSafeID("0b9f7a1c-1234-abcd_ef"))
        #expect(!ClaudeSessionFile.isSafeID("../escape"))
        #expect(!ClaudeSessionFile.isSafeID("a/b"))
        #expect(!ClaudeSessionFile.isSafeID(""))
    }

    /// The last main-thread assistant turn wins: the sidechain, the synthetic error and the user
    /// line after it (which mentions "assistant") are skipped.
    @Test func theLastMainTurnIsTheContext() throws {
        let data = try Data(contentsOf: Self.fixture)
        #expect(ClaudeSessionFile.lastContextTokens(in: data, cutAtStart: false) == 5 + 1208 + 183_000)
    }

    @Test func aLineCutByTheTailWindowIsDropped() throws {
        let data = try Data(contentsOf: Self.fixture)
        let lines = data.split(separator: UInt8(ascii: "\n"))
        // Starts inside the 184k turn: that line is cut, so the turn before it is not visible
        // either, and nothing counts.
        let cut = Data(lines[3].suffix(40)) + Data("\n".utf8) + lines[4...].map { Data($0) + Data("\n".utf8) }.reduce(Data(), +)
        #expect(ClaudeSessionFile.lastContextTokens(in: cut, cutAtStart: true) == nil)
        // The same text read from the file's start keeps its first line, which is whole.
        let whole = lines[2...].map { Data($0) + Data("\n".utf8) }.reduce(Data(), +)
        #expect(ClaudeSessionFile.lastContextTokens(in: whole, cutAtStart: true) == 5 + 1208 + 183_000)
    }

    @Test func anUnchangedFileIsNotReadAgain() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: Self.fixture.path)
        let size = try #require((attributes[.size] as? NSNumber)?.uint64Value)
        let modified = try #require(attributes[.modificationDate] as? Date)
        let remembered = ClaudeSessionFile.Reading(size: size, modified: modified, tokens: 42)
        #expect(try ClaudeSessionFile.read(Self.fixture, previous: remembered, tailBytes: 1024).tokens == 42)
        let older = ClaudeSessionFile.Reading(size: size - 1, modified: modified, tokens: 42)
        #expect(try ClaudeSessionFile.read(Self.fixture, previous: older, tailBytes: 1 << 20).tokens == 184_213)
    }

    /// The text of the last main-thread entry that has any: the tool call after it, the
    /// sidechain, the synthetic error and an empty "(no content)" do not count. Unknown fields and
    /// a missing `content` are fine.
    @Test func theLastMainTextIsTheFinalMessage() {
        let lines = [
            #"{"type":"assistant","message":{"model":"m","content":[{"type":"text","text":"Earlier."}]}}"#,
            #"{"type":"assistant","isSidechain":false,"future":1,"message":{"model":"m","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"  **Done.** Tests pass.\n\nPR is up.  "}],"usage":{"input_tokens":7}}}"#,
            #"{"type":"assistant","message":{"model":"m","content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#,
            #"{"type":"assistant","message":{"model":"m"}}"#,
            #"{"type":"assistant","message":{"model":"m","content":[{"type":"text","text":"(no content)"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"model":"m","content":[{"type":"text","text":"From a subagent."}]}}"#,
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"what did the assistant say?"}}"#,
        ]
        let turn = ClaudeSessionFile.lastTurn(in: Data(lines.joined(separator: "\n").utf8), cutAtStart: false)
        #expect(turn.finalMessage == "**Done.** Tests pass.\n\nPR is up.")
        #expect(turn.tokens == 7)
        // The fixture has usage but no text.
        #expect(ClaudeSessionFile.lastTurn(in: Data(#"{"type":"assistant","message":{"model":"m","usage":{"input_tokens":1}}}"#.utf8),
                                           cutAtStart: false).finalMessage == nil)
    }

    /// 1,100 bytes cut into the 14k turn but keep the 184k one whole.
    @Test func aSmallTailWindowStillFindsTheTurn() throws {
        let reading = try ClaudeSessionFile.read(Self.fixture, previous: nil, tailBytes: 1100)
        #expect(reading.tokens == 184_213)
    }
}

@MainActor
@Suite struct ClaudeContextReaderTests {
    let config: URL

    init() throws {
        config = FileManager.default.temporaryDirectory.appending(path: "shepherd-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: config.appending(path: "projects"), withIntermediateDirectories: true)
    }

    func install(id: String, folder: String) throws {
        let directory = config.appending(path: "projects").appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ClaudeSessionFileTests.fixture, to: directory.appending(path: "\(id).jsonl"))
    }

    @Test func readsTheSessionInItsWorkingDirectorysFolder() async throws {
        defer { try? FileManager.default.removeItem(at: config) }
        try install(id: "session-1", folder: "-tmp-project-1")
        let reader = ClaudeContextReader(configDirectory: config)
        let session = AgentSession(kind: "claude", id: "session-1", cwd: "/tmp/project-1")
        #expect(try await reader.read(session)?.contextTokens == 184_213)
        // Read again: unchanged, from the cache.
        #expect(try await reader.read(session)?.contextTokens == 184_213)
    }

    @Test func findsASessionThatMovedFolder() async throws {
        defer { try? FileManager.default.removeItem(at: config) }
        try install(id: "session-2", folder: "-tmp-elsewhere")
        let reader = ClaudeContextReader(configDirectory: config)
        let session = AgentSession(kind: "claude", id: "session-2", cwd: "/tmp/project-1")
        #expect(try await reader.read(session)?.contextTokens == 184_213)
    }

    @Test func otherKindsAndMissingFilesGiveNothing() async throws {
        defer { try? FileManager.default.removeItem(at: config) }
        try install(id: "session-3", folder: "-tmp-project-1")
        let reader = ClaudeContextReader(configDirectory: config)
        #expect(try await reader.read(AgentSession(kind: "codex", id: "session-3", cwd: "/tmp/project-1")) == nil)
        #expect(try await reader.read(AgentSession(kind: "claude", id: "missing", cwd: "/tmp/project-1")) == nil)
        #expect(try await reader.read(AgentSession(kind: "claude", id: "../session-3")) == nil)
    }
}
