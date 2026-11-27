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
        try await Task.sleep(for: .seconds(1.5))
        #expect(model.status == .unread(.count(2)))
    }

    @MainActor @Test func theCountFollowsTheDockWhilePolling() async throws {
        let reader = FakeReader(.label("1"))
        let model = TeamsUnreadModel(reader: reader)
        let polling = Task { await model.poll() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.status == .unread(.count(1)))
        let readsBefore = reader.reads
        polling.cancel()
        reader.reading = .label("7")
        try await Task.sleep(for: .milliseconds(300))
        // Cancelled: it stopped looking, so it never saw 7.
        #expect(model.status == .unread(.count(1)))
        #expect(reader.reads == readsBefore)
    }

    @Test func theRealReaderNeverShowsAPromptWhenOnlyAsked() {
        // `isAllowed` is a plain yes/no; whatever it says, it doesn't prompt. (On a machine without the
        // permission the real read says "not allowed", and on one with it, something else.)
        let reader = AccessibilityDockBadgeReader()
        _ = reader.isAllowed()
        if !reader.isAllowed() { #expect(reader.read() == .notAllowed) }
    }
#endif
