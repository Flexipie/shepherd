import Testing
@testable import HerdrKit

@Suite struct HerdrSocketTests {
    @Test func explicitPathWins() {
        let path = HerdrSocket.defaultPath(environment: ["HERDR_SOCKET_PATH": "/tmp/x.sock", "HERDR_SESSION": "dev"])
        #expect(path == "/tmp/x.sock")
    }

    @Test func namedSessionUsesSessionsDir() {
        let path = HerdrSocket.defaultPath(environment: ["HERDR_SESSION": "dev"])
        #expect(path.hasSuffix("/.config/herdr/sessions/dev/herdr.sock"))
    }

    @Test func defaultSession() {
        #expect(HerdrSocket.defaultPath(environment: [:]).hasSuffix("/.config/herdr/herdr.sock"))
    }
}
