// Writing the (temporary) hosts file: the deadline, crashes and stale blocks.

import Foundation
import Testing

@testable import NowboardKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let original = "127.0.0.1\tlocalhost\n::1 localhost\n10.0.0.5 nas.local\n"

/// A temporary hosts file and state file, and a clock the test moves.
private final class Setup: @unchecked Sendable {
    let dir: URL
    let hosts: String
    let state: String
    private let lock = NSLock()
    private var _now = t0
    private var _flushes = 0
    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }
    var flushes: Int { lock.withLock { _flushes } }

    init(_ text: String? = original) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-hosts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        hosts = dir.appendingPathComponent("hosts").path
        state = dir.appendingPathComponent("state/block.json").path
        if let text { try text.write(toFile: hosts, atomically: true, encoding: .utf8) }
    }

    func controller() -> HostsBlockController {
        HostsBlockController(hostsPath: hosts, statePath: state, now: { self.now }, flushNames: { self.lock.withLock { self._flushes += 1 } })
    }

    var text: String { (try? String(contentsOfFile: hosts, encoding: .utf8)) ?? "<unreadable>" }
    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

@Test func blockingAddsOurBlockAndFlushesTheNames() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    let until = try c.block(domains: ["youtube.com", "www.youtube.com"], until: t0.addingTimeInterval(1500))
    #expect(until == t0.addingTimeInterval(1500))
    #expect(s.text.hasPrefix(original))
    #expect(s.text.contains("127.0.0.1 youtube.com") && s.text.contains("::1 www.youtube.com"))
    #expect(s.flushes == 1)
    #expect(c.activeUntil == until)
}

@Test func unblockingGivesBackTheOriginalAndForgetsTheDeadline() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    try c.unblock()
    #expect(s.text == original)
    #expect(c.activeUntil == nil)
    #expect(!FileManager.default.fileExists(atPath: s.state))
    // Unblocking when nothing is blocked is fine, and leaves the file alone.
    try c.unblock()
    #expect(s.text == original)
}

@Test func blockingTwiceReplacesTheBlock() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    try c.block(domains: ["b.com"], until: t0.addingTimeInterval(900))
    #expect(!s.text.contains("a.com") && s.text.contains("b.com"))
    #expect(s.text.components(separatedBy: HostsBlock.startMarker).count == 2)
    #expect(c.activeUntil == t0.addingTimeInterval(900))
}

@Test func theNamesAreCheckedAgainAndBadOnesNeverReachTheFile() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    try c.block(domains: ["good.com", "bad name", "x.com\n127.0.0.1 bank.com", "1.2.3.4"], until: t0.addingTimeInterval(600))
    #expect(s.text.contains("good.com") && !s.text.contains("bank.com") && !s.text.contains("1.2.3.4"))
    #expect(throws: HostsBlockError.noValidDomains) { try c.block(domains: ["nope", ""], until: t0.addingTimeInterval(600)) }
    #expect(throws: HostsBlockError.noValidDomains) { try c.block(domains: [], until: t0.addingTimeInterval(600)) }
}

@Test func aDeadlineInThePastIsRefusedAndNothingChanges() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    #expect(throws: HostsBlockError.deadlineInThePast) { try c.block(domains: ["a.com"], until: t0) }
    #expect(throws: HostsBlockError.deadlineInThePast) { try c.block(domains: ["a.com"], until: t0.addingTimeInterval(-5)) }
    #expect(s.text == original)
    #expect(s.flushes == 0)
}

@Test func aDeadlineFarAwayIsCutToTheLongestBlock() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    let until = try c.block(domains: ["a.com"], until: t0.addingTimeInterval(10 * 24 * 3600))
    #expect(until == t0.addingTimeInterval(HostsBlockController.maxDuration))
}

@Test func theBlockEndsWhenItsTimeIsUp() throws {
    let s = try Setup(); defer { s.cleanup() }
    let c = s.controller()
    try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    s.now = t0.addingTimeInterval(599)
    #expect(try !c.expireIfDue())
    #expect(s.text != original)
    s.now = t0.addingTimeInterval(600)  // exactly at the end
    #expect(try c.expireIfDue())
    #expect(s.text == original)
    #expect(try !c.expireIfDue())  // nothing left to do
}

@Test func aRestartedHelperKeepsABlockThatIsStillRunning() throws {
    let s = try Setup(); defer { s.cleanup() }
    try s.controller().block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    s.now = t0.addingTimeInterval(100)
    // A new controller, like a helper that was restarted.
    let until = try s.controller().startup()
    #expect(until == t0.addingTimeInterval(600))
    #expect(s.text.contains("127.0.0.1 a.com"))
}

@Test func aRestartedHelperRemovesABlockWhoseTimeRanOut() throws {
    let s = try Setup(); defer { s.cleanup() }
    try s.controller().block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    s.now = t0.addingTimeInterval(3600)  // the Mac was off for an hour
    #expect(try s.controller().startup() == nil)
    #expect(s.text == original)
    #expect(!FileManager.default.fileExists(atPath: s.state))
}

@Test func aStaleBlockWithNoDeadlineIsRemovedAtStart() throws {
    // The app or helper crashed after the block was written but the deadline was lost.
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: original)
    let s = try Setup(blocked); defer { s.cleanup() }
    #expect(try s.controller().startup() == nil)
    #expect(s.text == original)
}

@Test func aRestoredBlockIsPutBackIfTheFileLostIt() throws {
    let s = try Setup(); defer { s.cleanup() }
    try s.controller().block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    try original.write(toFile: s.hosts, atomically: true, encoding: .utf8)  // someone restored the old file
    #expect(try s.controller().startup() == t0.addingTimeInterval(600))
    #expect(s.text.contains("127.0.0.1 a.com"))
}

@Test func aBrokenOrTamperedDeadlineFileMeansNoBlock() throws {
    let s = try Setup(); defer { s.cleanup() }
    try FileManager.default.createDirectory(atPath: (s.state as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try "not json".write(toFile: s.state, atomically: true, encoding: .utf8)
    #expect(try s.controller().startup() == nil)
    // Names in the state file are checked again before they are written.
    let evil = #"{"until":"2027-01-15T09:00:00Z","domains":["x.com\n127.0.0.1 bank.com","ok.com"]}"#
    try evil.write(toFile: s.state, atomically: true, encoding: .utf8)
    s.now = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
    _ = try s.controller().startup()
    #expect(s.text.contains("ok.com") && !s.text.contains("bank.com"))
}

@Test func aHostsFileThatIsNotTextIsLeftAlone() throws {
    let s = try Setup(nil); defer { s.cleanup() }
    let bytes = Data([0xFF, 0xFE, 0x00, 0x41])
    try bytes.write(to: URL(fileURLWithPath: s.hosts))
    let c = s.controller()
    #expect(throws: HostsBlockError.self) { try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600)) }
    #expect(try Data(contentsOf: URL(fileURLWithPath: s.hosts)) == bytes)
}

@Test func aMissingHostsFileIsCreatedWithJustTheBlock() throws {
    let s = try Setup(nil); defer { s.cleanup() }
    try s.controller().block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    #expect(s.text.hasPrefix(HostsBlock.startMarker))
    try s.controller().unblock()
    #expect(s.text == "")
}

@Test func theFilePermissionsAreKeptAndNoTemporaryFileIsLeft() throws {
    let s = try Setup(); defer { s.cleanup() }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.hosts)
    let c = s.controller()
    try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    let mode = (try FileManager.default.attributesOfItem(atPath: s.hosts)[.posixPermissions] as? NSNumber)?.intValue
    #expect(mode == 0o644)
    try c.unblock()
    let names = try FileManager.default.contentsOfDirectory(atPath: s.dir.path)
    #expect(!names.contains { $0.hasPrefix(".hosts") })  // no `.hosts.nowboard-…` left behind
}

@Test func aLinkedHostsFileIsWrittenWhereItReallyIs() throws {
    // /etc/hosts is a link on a Mac: the link must stay a link, the real file changes.
    let s = try Setup(); defer { s.cleanup() }
    let link = s.dir.appendingPathComponent("link-to-hosts").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: s.hosts)
    let c = HostsBlockController(hostsPath: link, statePath: s.state, now: { t0 }, flushNames: {})
    try c.block(domains: ["a.com"], until: t0.addingTimeInterval(600))
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == s.hosts)
    #expect(s.text.contains("a.com"))
}
