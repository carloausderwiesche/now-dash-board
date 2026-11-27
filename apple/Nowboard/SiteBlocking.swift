// Blocking distracting sites during a focus session, the app's side
// (docs/adr/0019). The privileged work is done by a helper program that
// macOS runs as root after the user approves it once; the app asks it, over
// XPC, to block some sites until a time, and to unblock them.
//
// Nothing here changes the hosts file. If the helper isn't set up the app
// says so and does nothing else.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Observation
    import Security
    import ServiceManagement

    // MARK: - Registration of the helper

    /// Where the helper stands with macOS (a protocol, so tests use a fake).
    enum HelperRegistrationStatus: Equatable {
        case notRegistered
        /// Registered, but the user hasn't approved it yet in System Settings.
        case requiresApproval
        case enabled
        /// The helper's description isn't in the app (a build problem).
        case notFound
    }

    protocol HelperRegistration: Sendable {
        var status: HelperRegistrationStatus { get }
        /// Asks macOS to register the helper. The user then approves it in System Settings.
        func register() throws
        func openSystemSettings()
    }

    /// The real thing: `SMAppService`, macOS's way of installing a helper that comes inside the app.
    struct SMAppServiceRegistration: HelperRegistration {
        private var service: SMAppService { SMAppService.daemon(plistName: FocusBlockHelperNames.plistName) }

        var status: HelperRegistrationStatus {
            switch service.status {
            case .notRegistered: .notRegistered
            case .requiresApproval: .requiresApproval
            case .enabled: .enabled
            case .notFound: .notFound
            @unknown default: .notRegistered
            }
        }

        func register() throws { try service.register() }
        func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: - Talking to the helper

    /// Asks the helper to block and unblock (a protocol, so tests use a fake). Each answer is nil for
    /// "worked", or a sentence saying why not.
    protocol FocusBlockClient: Sendable {
        func block(domains: [String], until: Date) async -> String?
        func unblock() async -> String?
    }

    /// The real client: an XPC connection to the helper.
    ///
    /// It only talks to a helper signed by the same developer team as the app. An app signed ad hoc
    /// (no team) can't say who the helper is, so it doesn't talk at all.
    struct XPCFocusBlockClient: FocusBlockClient {
        func block(domains: [String], until: Date) async -> String? {
            await call { proxy, done in proxy.block(domains: domains, until: until, reply: done) }
        }

        func unblock() async -> String? {
            await call { proxy, done in proxy.unblock(reply: done) }
        }

        /// The rule the helper's code signature must meet, or nil if this app has no team signature.
        static func helperRequirement() -> String? {
            var code: SecCode?
            var staticCode: SecStaticCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code, SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
                let staticCode
            else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                let dictionary = info as? [String: Any], let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
                team.wholeMatch(of: /[A-Z0-9]{10}/) != nil
            else { return nil }
            return "identifier \"\(FocusBlockHelperNames.helperBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }

        /// Opens a connection, makes one call, and closes it again.
        private func call(_ work: @escaping (FocusBlockHelperProtocol, @escaping (String?) -> Void) -> Void) async -> String? {
            guard let requirement = Self.helperRequirement() else {
                return "This build of Nowboard has no developer-team signature, so it can't verify the helper."
            }
            return await withCheckedContinuation { continuation in
                // `.privileged` is how a root daemon is addressed.
                let connection = NSXPCConnection(machServiceName: FocusBlockHelperNames.machServiceName, options: .privileged)
                connection.setCodeSigningRequirement(requirement)
                connection.remoteObjectInterface = {
                    let interface = NSXPCInterface(with: FocusBlockHelperProtocol.self)
                    let strings = NSSet(array: [NSArray.self, NSString.self]) as! Set<AnyHashable>
                    interface.setClasses(strings, for: #selector(FocusBlockHelperProtocol.block(domains:until:reply:)), argumentIndex: 0, ofReply: false)
                    return interface
                }()
                // Answer exactly once, whichever of "reply" and "error" comes.
                let once = Once { message in
                    connection.invalidate()
                    continuation.resume(returning: message)
                }
                connection.invalidationHandler = { once.fire("The helper isn't answering.") }
                guard
                    let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                        once.fire("The helper isn't answering: \(error.localizedDescription)")
                    }) as? FocusBlockHelperProtocol
                else {
                    once.fire("The helper isn't answering.")
                    return
                }
                connection.resume()
                work(proxy) { message in once.fire(message) }
            }
        }
    }

    /// Runs a closure at most once, from any thread.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let action: (String?) -> Void
        init(_ action: @escaping (String?) -> Void) { self.action = action }
        func fire(_ message: String?) {
            let first = lock.withLock { () -> Bool in
                defer { done = true }
                return !done
            }
            if first { action(message) }
        }
    }

    // MARK: - What the box knows

    /// Whether the helper is ready, and whether sites are blocked right now.
    @MainActor @Observable
    final class SiteBlockModel {
        enum State: Equatable {
            /// The helper isn't set up: the box offers a button.
            case notSetUp
            /// Registered, waiting for the user's approval in System Settings.
            case needsApproval
            /// Ready: nothing is blocked now.
            case ready
            /// Sites are blocked until this time.
            case active(until: Date)
            /// The last try failed; the sentence says why.
            case failed(String)
        }

        private(set) var state: State = .notSetUp

        @ObservationIgnored private let registration: any HelperRegistration
        @ObservationIgnored private let client: any FocusBlockClient
        /// What the session wants: the end time while it runs, else nil. And the names to block.
        @ObservationIgnored private var wantedUntil: Date?
        @ObservationIgnored private var wantedDomains: [String] = []
        @ObservationIgnored private var work: Task<Void, Never>?

        init(registration: any HelperRegistration = SMAppServiceRegistration(), client: any FocusBlockClient = XPCFocusBlockClient()) {
            self.registration = registration
            self.client = client
            refreshRegistration()
        }

        /// Looks at the helper's state with macOS (cheap; no helper call).
        func refreshRegistration() {
            switch registration.status {
            case .enabled:
                if case .active = state {} else if case .failed = state {} else { state = .ready }
            case .requiresApproval: state = .needsApproval
            case .notRegistered, .notFound: state = .notSetUp
            }
        }

        /// The "Set up" button: registers the helper. macOS then asks the user to approve it.
        func setUp() {
            do {
                try registration.register()
            } catch {
                state = .failed("Couldn't set up site blocking: \(error.localizedDescription)")
                return
            }
            refreshRegistration()
            if registration.status == .requiresApproval { registration.openSystemSettings() }
        }

        func openSettings() { registration.openSystemSettings() }

        /// The session or the settings changed: block until `until` (when sites should be blocked), or unblock.
        /// `until` is nil when no session is running or blocking is switched off. Never touches the helper
        /// unless it is set up and approved.
        func update(until: Date?, entries: [String]) {
            wantedUntil = until
            wantedDomains = BlockedSites.domains(for: entries)
            refreshRegistration()
            guard registration.status == .enabled else { return }
            // One request at a time, in order: a later one waits for the one before.
            let previous = work
            let until = wantedUntil, domains = wantedDomains
            work = Task { [client] in
                await previous?.value
                if let until, !domains.isEmpty {
                    let problem = await client.block(domains: domains, until: until)
                    self.finished(problem: problem, active: until)
                } else {
                    let problem = await client.unblock()
                    self.finished(problem: problem, active: nil)
                }
            }
        }

        /// Waits for the last request (for tests).
        func settle() async { await work?.value }

        private func finished(problem: String?, active: Date?) {
            if let problem {
                state = .failed(problem)
            } else if let active {
                state = .active(until: active)
            } else {
                state = .ready
            }
        }
    }
#endif
