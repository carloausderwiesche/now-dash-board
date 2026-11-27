// The Teams box's model with a fake Dock reader: what it shows, that it
// never asks for permission by itself, and that it looks again.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Testing

    @testable import Nowboard

    /// Answers with whatever the test says and counts what the model asked for.
    private final class FakeReader: DockBadgeReader, @unchecked Sendable {
        private let lock = NSLock()
        private var _reading: DockBadgeReading
        private var _reads = 0
        private var _requests = 0
        init(_ reading: DockBadgeReading) { _reading = reading }
        var reading: DockBadgeReading {
            get { lock.withLock { _reading } }
            set { lock.withLock { _reading = newValue } }
        }
        var reads: Int { lock.withLock { _reads } }
        var requests: Int { lock.withLock { _requests } }
        func isAllowed() -> Bool { reading != .notAllowed }
        func read() -> DockBadgeReading { lock.withLock { _reads += 1; return _reading } }
        func requestAccess() { lock.withLock { _requests += 1 } }
    }

    @MainActor @Test func theModelShowsNothingUntilItHasLooked() {
        let model = TeamsUnreadModel(reader: FakeReader(.label("3")))
        #expect(model.status == nil)
        #expect(model.display == nil)
    }

    @MainActor @Test(arguments: [
        (DockBadgeReading.label("3"), TeamsStatus.unread(.count(3))),
        (.label(nil), .unread(.none)),
        (.label("99+"), .unread(.atLeast(99))),
        (.label("•"), .unread(.unknown)),
        (.notRunning, .notRunning),
        (.notInDock, .notInDock),
        (.notAllowed, .notAllowed),
    ])
    func whatTheDockSaysBecomesTheStatus(reading: DockBadgeReading, expected: TeamsStatus) async {
        let model = TeamsUnreadModel(reader: FakeReader(reading))
        await model.refresh()
        #expect(model.status == expected)
    }

    @MainActor @Test func lookingNeverAsksForPermission() async {
        let reader = FakeReader(.notAllowed)
        let model = TeamsUnreadModel(reader: reader)
        await model.refresh()
        await model.refresh()
        #expect(model.display?.needsPermission == true)
        #expect(reader.requests == 0)  // only the button asks
    }

    @MainActor @Test func theButtonAsksForPermissionAndThenLooksAgain() async throws {
        let reader = FakeReader(.notAllowed)
        let model = TeamsUnreadModel(reader: reader)
        await model.refresh()
        reader.reading = .label("2")  // the person allowed it in System Settings
        model.requestAccess()
        #expect(reader.requests == 1)
        // It looks again about a second later: wait for that (up to 10 s) instead of guessing a time.
        for _ in 0..<200 where model.status != .unread(.count(2)) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.status == .unread(.count(2)))
    }

    @MainActor @Test func aLookThatGotNoAnswerKeepsWhatWasShown() async {
        let reader = FakeReader(.label("4"))
        let model = TeamsUnreadModel(reader: reader)
        await model.refresh()
        #expect(model.status == .unread(.count(4)))
        reader.reading = .failed  // the Dock was busy this time
        await model.refresh()
        #expect(model.status == .unread(.count(4)))  // not "0", not "no Dock icon"
        reader.reading = .label("5")
        await model.refresh()
        #expect(model.status == .unread(.count(5)))
    }

    @MainActor @Test func pollingLooksRepeatedlyAndForgetsTheReadingWhenItStops() async throws {
        let reader = FakeReader(.label("1"))
        let model = TeamsUnreadModel(reader: reader)
        let polling = Task { await model.poll() }
        for _ in 0..<200 where model.status == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.status == .unread(.count(1)))
        polling.cancel()
        await polling.value
        // The box left the screen: no stale number is kept for when it comes back.
        #expect(model.status == nil)
        let readsAfterStop = reader.reads
        try await Task.sleep(for: .milliseconds(300))
        #expect(reader.reads == readsAfterStop)  // and it has stopped looking
    }

    @Test func onlyTheTeamsDockItemCounts() {
        for title in ["Microsoft Teams", "Microsoft Teams (work or school)", "Teams", "  teams ", "MICROSOFT TEAMS"] {
            #expect(AccessibilityDockBadgeReader.isTeams(title), "\(title)")
        }
        for title in ["Steam", "Steamed Teams Toolkit", "Teams Toolkit", "Notes", "", "Team"] {
            #expect(!AccessibilityDockBadgeReader.isTeams(title), "\(title)")
        }
    }

    @Test func theRealReaderNeverShowsAPromptWhenOnlyAsked() {
        // `isAllowed` is a plain yes/no; whatever it says, it doesn't prompt. (On a machine without the
        // permission the real read says "not allowed", and on one with it, something else.)
        let reader = AccessibilityDockBadgeReader()
        _ = reader.isAllowed()
        if !reader.isAllowed() { #expect(reader.read() == .notAllowed) }
    }
#endif
