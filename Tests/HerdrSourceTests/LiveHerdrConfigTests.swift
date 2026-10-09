import Foundation
import Testing
@testable import HerdrSource

/// Reads this machine's herdr config. Skipped unless `SHEPHERD_LIVE=1`; prints nothing from it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERD_LIVE"] == "1"))
struct LiveHerdrConfigTests {
    @Test func realConfigReadsWithoutProblems() throws {
        let data = try Data(contentsOf: HerdrSidebar.configURL())
        let document = TOMLDocument(data)
        #expect(document.problems.isEmpty, "\(document.problems)")
        #expect(HerdrSidebar.read(data).problems.isEmpty)
    }
}
