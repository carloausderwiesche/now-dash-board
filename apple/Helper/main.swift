// The helper: a small program that macOS runs as root, after the user has
// approved it once in System Settings (docs/adr/0019). It does one job: while a
// focus session runs, it keeps a block of site names in /etc/hosts, and it
// removes that block when the time is up, whatever happens to the app.
//
// It runs as root, so it is built to trust nobody:
//   - It answers only callers whose code signature says "the Nowboard app, signed
//     by the same developer team as this helper" (`setCodeSigningRequirement`).
//     If this helper has no team signature (an ad-hoc build) it can't tell who
//     is calling, so it answers nobody.
//   - It checks every site name itself, again, and cuts the time to at most four hours.
//   - It can only add and remove its own marked block (`HostsBlock`). Nothing else in
//     /etc/hosts is touched, and it runs no command with anything the caller sent.
//   - It keeps its own deadline and checks it every few seconds, so a crash or a
//     closed app can't leave the sites blocked.

import Foundation
import NowboardKit
import Security

// MARK: - The work

/// Does the blocking, one request at a time on its own queue.
///
/// Swift note: `@unchecked Sendable` means "I promise this is safe to use from several threads":
/// here every use goes through one serial queue, which makes it so.
final class BlockEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nowboard.helper.engine")
    private let controller: HostsBlockController
    private var timer: DispatchSourceTimer?

    init() {
        controller = HostsBlockController(
            hostsPath: "/etc/hosts", statePath: "/Library/Application Support/Nowboard/block.json", flushNames: BlockEngine.flushNames)
    }

    /// At launch: remove a stale block (or keep one that is still running), then check the deadline every 10 seconds.
    func start() {
        queue.sync { _ = try? controller.startup() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [controller] in _ = try? controller.expireIfDue() }
        timer.resume()
        self.timer = timer
    }

    func block(domains: [String], until: Date) -> String? {
        queue.sync {
            do {
                try controller.block(domains: domains, until: until)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    func unblock() -> String? {
        queue.sync {
            do {
                try controller.unblock()
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    func activeUntil() -> Date? { queue.sync { controller.activeUntil } }

    /// Makes the Mac forget the names it remembers, so a change counts at once. Fixed commands with
    /// fixed arguments: nothing the caller sent is ever part of them.
    static func flushNames() {
        for (path, arguments) in [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}

/// What a connected caller can ask. It only passes the request on to the engine.
final class HelperService: NSObject, FocusBlockHelperProtocol {
    private let engine: BlockEngine
    init(engine: BlockEngine) { self.engine = engine }

    func block(domains: [String], until: Date, reply: @escaping (String?) -> Void) {
        reply(engine.block(domains: domains, until: until))
    }

    func unblock(reply: @escaping (String?) -> Void) {
        reply(engine.unblock())
    }

    func activeUntil(reply: @escaping (Date?) -> Void) {
        reply(engine.activeUntil())
    }
}

// MARK: - Who may call

/// The rule a caller's code signature must meet, or nil if this helper can't tell who is calling.
///
/// The caller must be the Nowboard app and signed by the same developer team as this helper. The
/// team comes from this helper's own signature: a program signed by a different team (or not at
/// all) can't satisfy it. An ad-hoc signed helper has no team, so there is no rule: nobody is let in.
func callerRequirement() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code, SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
        let staticCode
    else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
        let dictionary = info as? [String: Any], let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    else { return nil }
    // A team id is ten letters and digits; anything else is not trusted.
    guard team.wholeMatch(of: /[A-Z0-9]{10}/) != nil else { return nil }
    return "identifier \"\(FocusBlockHelperNames.appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
}

/// Decides, for each connection, whether to answer it.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let engine: BlockEngine
    private let requirement: String?

    init(engine: BlockEngine, requirement: String?) {
        self.engine = engine
        self.requirement = requirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // No rule means we can't verify anyone: refuse.
        guard let requirement else { return false }
        // From now on macOS drops any message from a caller that doesn't meet the rule.
        connection.setCodeSigningRequirement(requirement)
        let interface = NSXPCInterface(with: FocusBlockHelperProtocol.self)
        // The list of names is an array of strings: say so, or XPC refuses it.
        let strings = NSSet(array: [NSArray.self, NSString.self]) as! Set<AnyHashable>
        interface.setClasses(strings, for: #selector(FocusBlockHelperProtocol.block(domains:until:reply:)), argumentIndex: 0, ofReply: false)
        connection.exportedInterface = interface
        connection.exportedObject = HelperService(engine: engine)
        connection.resume()
        return true
    }
}

// MARK: - Start

let engine = BlockEngine()
engine.start()
let delegate = ListenerDelegate(engine: engine, requirement: callerRequirement())
let listener = NSXPCListener(machServiceName: FocusBlockHelperNames.machServiceName)
listener.delegate = delegate
listener.resume()
// Keep running and wait for callers.
RunLoop.main.run()
