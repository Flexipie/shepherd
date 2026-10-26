import Darwin
import Testing
@testable import HerdrSource

@Suite struct HerdrProcessesTests {
    @Test func findsProcessesByName() {
        // Only the user's own processes can be named, which is all herdr needs.
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = proc_name(getpid(), &buffer, UInt32(buffer.count))
        let ownName = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        #expect(HerdrProcesses.pids(named: ownName).contains(getpid()))
    }
}
