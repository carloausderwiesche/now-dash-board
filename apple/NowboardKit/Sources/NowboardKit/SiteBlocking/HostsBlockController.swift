// The part that writes the real hosts file (the helper uses it; tests use a
// temporary file). It adds and removes the marked block (`HostsBlock`), keeps
// the deadline, and clears a stale block: a crash of the app or of the helper
// must never leave the person blocked for good.
//
// Swift note: the clock and the "refresh the name cache" step are passed in as
// closures, so tests can move time and don't run system programs.

import Foundation

public enum HostsBlockError: Error, Equatable, LocalizedError {
    /// None of the names was a valid host name.
    case noValidDomains
    /// The end time is not in the future.
    case deadlineInThePast
    /// The hosts file couldn't be read as text (so it is left alone).
    case unreadable(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noValidDomains: "No valid site names to block."
        case .deadlineInThePast: "The blocking time is already over."
        case .unreadable(let why): "The hosts file can't be read: \(why)"
        case .writeFailed(let why): "The hosts file can't be written: \(why)"
        }
    }
}

/// What is remembered while a block is on: until when, and which names.
struct HostsBlockState: Codable, Equatable {
    var until: Date
    var domains: [String]
}

public final class HostsBlockController {
    /// A block never lasts longer than this, whatever the caller asks for (a session is at most 3 hours).
    public static let maxDuration: TimeInterval = 4 * 3600

    private let hostsPath: String
    private let statePath: String
    private let now: () -> Date
    private let flushNames: () -> Void

    /// - `hostsPath`: the hosts file (`/etc/hosts`).
    /// - `statePath`: where the deadline is kept, so a restarted helper still knows it.
    /// - `flushNames`: refreshes the Mac's name cache after a change, so it counts at once.
    public init(
        hostsPath: String = "/etc/hosts", statePath: String, now: @escaping () -> Date = { Date() },
        flushNames: @escaping () -> Void = {}
    ) {
        self.hostsPath = hostsPath
        self.statePath = statePath
        self.now = now
        self.flushNames = flushNames
    }

    // MARK: - Actions

    /// Blocks `domains` until `until` (at most `maxDuration` from now). The names are checked again here,
    /// whoever sent them. Returns the end time actually used. Doing it again just replaces the block.
    @discardableResult
    public func block(domains: [String], until: Date) throws -> Date {
        let clean = HostsBlock.sanitize(domains)
        guard !clean.isEmpty else { throw HostsBlockError.noValidDomains }
        let current = now()
        guard until > current else { throw HostsBlockError.deadlineInThePast }
        let deadline = min(until, current.addingTimeInterval(Self.maxDuration))
        try modifyHosts { HostsBlock.inserting(domains: clean, into: $0) }
        try saveState(HostsBlockState(until: deadline, domains: clean))
        flushNames()
        return deadline
    }

    /// Takes our block out and forgets the deadline.
    public func unblock() throws {
        try modifyHosts { HostsBlock.removing(from: $0) }
        try? FileManager.default.removeItem(atPath: statePath)
        flushNames()
    }

    /// For the helper's start: a block whose time has run out, or that has no remembered deadline (a crash
    /// in between), is removed. A block still running is put back as it was. Returns its end time if it is still on.
    @discardableResult
    public func startup() throws -> Date? {
        guard let state = loadState(), state.until > now() else {
            try unblock()
            return nil
        }
        try modifyHosts { HostsBlock.inserting(domains: state.domains, into: $0) }
        flushNames()
        return state.until
    }

    /// Removes the block if its time is up. Returns whether it did.
    @discardableResult
    public func expireIfDue() throws -> Bool {
        guard let state = loadState() else { return false }
        guard state.until <= now() else { return false }
        try unblock()
        return true
    }

    /// When the block ends, if one is on.
    public var activeUntil: Date? {
        guard let state = loadState(), state.until > now() else { return nil }
        return state.until
    }

    // MARK: - Files

    /// Reads the hosts file, changes its text, and writes it back all at once (a temporary file next
    /// to it, then a rename), so nobody ever reads half a file. Writes only if the text changed.
    private func modifyHosts(_ change: (String) -> String) throws {
        // /etc is a link to /private/etc on a Mac: write where the file really is.
        let target = URL(fileURLWithPath: hostsPath).resolvingSymlinksInPath()
        let original: String
        if FileManager.default.fileExists(atPath: target.path) {
            guard let data = try? Data(contentsOf: target), let text = String(data: data, encoding: .utf8) else {
                throw HostsBlockError.unreadable("not valid UTF-8 text")
            }
            original = text
        } else {
            original = ""
        }
        let changed = change(original)
        guard changed != original else { return }

        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).nowboard-\(UUID().uuidString)")
        do {
            try Data(changed.utf8).write(to: temp)
            // Same permissions as before (hosts is world-readable); `rename` replaces the file in one step.
            let mode = (try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber) ?? NSNumber(value: 0o644)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
            guard Darwin.rename(temp.path, target.path) == 0 else {
                throw HostsBlockError.writeFailed(String(cString: strerror(errno)))
            }
        } catch let error as HostsBlockError {
            try? FileManager.default.removeItem(at: temp)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw HostsBlockError.writeFailed(error.localizedDescription)
        }
    }

    private func loadState() -> HostsBlockState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(HostsBlockState.self, from: data) else { return nil }
        // Never trust what is in the file more than a fresh request: the names are checked again.
        let clean = HostsBlock.sanitize(state.domains)
        return clean.isEmpty ? nil : HostsBlockState(until: state.until, domains: clean)
    }

    private func saveState(_ state: HostsBlockState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let url = URL(fileURLWithPath: statePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            // The block is already in the hosts file but its deadline isn't kept: take it out again.
            try? modifyHosts { HostsBlock.removing(from: $0) }
            throw HostsBlockError.writeFailed("the deadline can't be saved: \(error.localizedDescription)")
        }
    }
}
