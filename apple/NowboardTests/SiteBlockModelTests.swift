// Site blocking in the app: when it asks the helper, and when it must not.
// A fake helper and a fake registration: nothing here touches /etc/hosts.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Testing

    @testable import Nowboard

    private final class FakeClient: FocusBlockClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        private var _problem: String?
        var calls: [String] { lock.withLock { _calls } }
        var problem: String? {
            get { lock.withLock { _problem } }
            set { lock.withLock { _problem = newValue } }
        }
        func block(domains: [String], until: Date) async -> String? {
            lock.withLock { _calls.append("block \(domains.count) \(Int(until.timeIntervalSince1970))") }
            return problem
        }
        func unblock() async -> String? {
            lock.withLock { _calls.append("unblock") }
            return problem
        }
    }

    private final class FakeRegistration: HelperRegistration, @unchecked Sendable {
        private let lock = NSLock()
        private var _status: HelperRegistrationStatus
        private var _registered = 0
        private var _opened = 0
        var failRegister = false
        init(_ status: HelperRegistrationStatus) { _status = status }
        var status: HelperRegistrationStatus {
            get { lock.withLock { _status } }
            set { lock.withLock { _status = newValue } }
        }
        var registered: Int { lock.withLock { _registered } }
        var opened: Int { lock.withLock { _opened } }
        func register() throws {
            lock.withLock { _registered += 1 }
            if failRegister { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no"]) }
            lock.withLock { _status = .requiresApproval }
        }
        func openSystemSettings() { lock.withLock { _opened += 1 } }
    }

    private let end = Date(timeIntervalSince1970: 1_800_001_500)

    @MainActor @Test func aRunningSessionBlocksTheExpandedNamesUntilItsEnd() async {
        let client = FakeClient()
        let model = SiteBlockModel(registration: FakeRegistration(.enabled), client: client)
        model.update(until: end, entries: ["youtube.com", "example.org"])
        await model.settle()
        // youtube.com stands for 5 names, example.org for 2 (itself and www).
        #expect(client.calls == ["block 7 1800001500"])
        #expect(model.state == .active(until: end))
    }

    @MainActor @Test func aSessionThatStopsRunningUnblocks() async {
        let client = FakeClient()
        let model = SiteBlockModel(registration: FakeRegistration(.enabled), client: client)
        model.update(until: end, entries: ["youtube.com"])
        model.update(until: nil, entries: [])  // paused, finished or reset
        await model.settle()
        #expect(client.calls.map { $0.prefix(5) } == ["block", "unblo"])
        #expect(model.state == .ready)
    }

    @MainActor @Test func requestsAreSentInTheOrderTheyWereMade() async {
        let client = FakeClient()
        let model = SiteBlockModel(registration: FakeRegistration(.enabled), client: client)
        for _ in 0..<5 {
            model.update(until: end, entries: ["a.com"])
            model.update(until: nil, entries: [])
        }
        await model.settle()
        #expect(client.calls.count == 10)
        #expect(client.calls.enumerated().allSatisfy { $0.offset % 2 == 0 ? $0.element.hasPrefix("block") : $0.element == "unblock" })
    }

    @MainActor @Test func nothingIsBlockedWhenBlockingIsSwitchedOffOrTheListIsEmpty() async {
        let client = FakeClient()
        let model = SiteBlockModel(registration: FakeRegistration(.enabled), client: client)
        // The dashboard passes no entries when blocking is off: that unblocks, it never blocks.
        model.update(until: end, entries: [])
        await model.settle()
        #expect(client.calls == ["unblock"])
        // Names that aren't valid give no block either.
        model.update(until: end, entries: ["not valid", "1.2.3.4"])
        await model.settle()
        #expect(client.calls == ["unblock", "unblock"])
    }

    @MainActor @Test func theHelperIsNeverCalledUntilItIsSetUpAndApproved() async {
        for status in [HelperRegistrationStatus.notRegistered, .requiresApproval, .notFound] {
            let client = FakeClient()
            let model = SiteBlockModel(registration: FakeRegistration(status), client: client)
            model.update(until: end, entries: ["youtube.com"])
            await model.settle()
            #expect(client.calls.isEmpty, "\(status)")
            #expect(model.state != .ready)
        }
    }

    @MainActor @Test func theStateFollowsTheRegistration() {
        #expect(SiteBlockModel(registration: FakeRegistration(.notRegistered), client: FakeClient()).state == .notSetUp)
        #expect(SiteBlockModel(registration: FakeRegistration(.notFound), client: FakeClient()).state == .notSetUp)
        #expect(SiteBlockModel(registration: FakeRegistration(.requiresApproval), client: FakeClient()).state == .needsApproval)
        #expect(SiteBlockModel(registration: FakeRegistration(.enabled), client: FakeClient()).state == .ready)
    }

    @MainActor @Test func setUpRegistersAndSendsThePersonToSystemSettings() {
        let registration = FakeRegistration(.notRegistered)
        let model = SiteBlockModel(registration: registration, client: FakeClient())
        model.setUp()
        #expect(registration.registered == 1)
        #expect(model.state == .needsApproval)
        #expect(registration.opened == 1)  // the approval happens in System Settings
    }

    @MainActor @Test func aFailedRegistrationIsReportedInWords() {
        let registration = FakeRegistration(.notRegistered)
        registration.failRegister = true
        let model = SiteBlockModel(registration: registration, client: FakeClient())
        model.setUp()
        if case .failed(let message) = model.state { #expect(message.contains("Couldn't set up")) } else { Issue.record("expected a failure") }
    }

    @MainActor @Test func aHelperThatSaysNoIsShownAndTheBoxDoesNotPretendToBlock() async {
        let client = FakeClient()
        client.problem = "The helper isn't answering."
        let model = SiteBlockModel(registration: FakeRegistration(.enabled), client: client)
        model.update(until: end, entries: ["youtube.com"])
        await model.settle()
        #expect(model.state == .failed("The helper isn't answering."))
    }

    @MainActor @Test func theSessionModelReportsItsEndSoTheBlockFollowsIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-sb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BoardStore(testFolder: dir)
        let session = FocusSessionModel()
        let seen = Seen()
        session.onRunningEndChange = { seen.add($0) }
        session.attach(to: store)
        session.start()
        session.pause()
        session.resume()
        session.reset()
        // attach (idle) → nil; start → end; pause → nil; resume → end; reset → nil.
        let kinds = seen.values.map { $0 == nil ? "nil" : "end" }
        #expect(kinds == ["nil", "end", "nil", "end", "nil"])
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Date?] = []
        var values: [Date?] { lock.withLock { _values } }
        func add(_ d: Date?) { lock.withLock { _values.append(d) } }
    }

    @Test func theSettingsKeepTheSiteListAndOldSettingsGetTheDefaults() throws {
        let old = #"{"theme":"braun","density":"roomy","categories":[{"id":"work","name":"Work","color":"blue"}]}"#
        let decoded = try JSONDecoder().decode(DeviceSettings.self, from: Data(old.utf8))
        #expect(decoded.blockSites)  // on by default
        #expect(decoded.blockedSites == BlockedSites.defaults)
        var settings = DeviceSettings()
        settings.blockSites = false
        settings.blockedSites = ["example.org"]
        let again = try JSONDecoder().decode(DeviceSettings.self, from: JSONEncoder().encode(settings))
        #expect(!again.blockSites && again.blockedSites == ["example.org"])
    }

    @Test func theHelperRuleNeedsATeamSignature() {
        // Only the rule is looked at: this test never calls the real helper (a team-signed test build
        // would otherwise reach the real one). The test app is signed ad hoc: no team, so no rule.
        let rule = XPCFocusBlockClient.helperRequirement()
        if let rule {
            #expect(rule.contains("identifier \"\(FocusBlockHelperNames.helperBundleID)\""))
            #expect(rule.contains("anchor apple generic"))
        }
    }
#endif
