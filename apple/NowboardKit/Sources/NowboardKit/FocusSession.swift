// The focus session: a countdown you start on one task. This file is the rules
// only (no screen, no timer): every state change takes the current time as a
// parameter, so tests can move the clock wherever they like.
//
// The countdown is based on the wall-clock END TIME, not on counting ticks.
// A Mac that sleeps for ten minutes then simply finds the end ten minutes
// closer, and nothing drifts.

import Foundation

/// A focus session and where it is.
///
/// Swift note: `Codable` lets the whole value be turned into JSON and back
/// (to be remembered between launches). An `enum` with values attached
/// (`running(end:)`) is a "one of these, each with its own data" type.
public struct FocusSession: Equatable, Codable, Sendable {
    public enum Phase: Equatable, Codable, Sendable {
        /// Nothing started: length and task can be chosen.
        case idle
        /// Counting down to this moment.
        case running(end: Date)
        /// Stopped with this much time left (seconds).
        case paused(remaining: TimeInterval)
        /// The time ran out.
        case finished
    }

    public private(set) var phase: Phase
    /// The chosen length, in whole minutes (1 to 180).
    public private(set) var minutes: Int
    /// The task this session is for (a task file name), or nil for "just focus".
    public private(set) var taskID: String?

    public static let minMinutes = 1
    public static let maxMinutes = 180
    public static let defaultMinutes = 25
    /// The quick choices.
    public static let presets = [15, 25, 50]

    public init(minutes: Int = defaultMinutes, taskID: String? = nil) {
        self.phase = .idle
        self.minutes = FocusSession.isValid(minutes: minutes) ? minutes : FocusSession.defaultMinutes
        self.taskID = taskID
    }

    // MARK: - Length

    public static func isValid(minutes: Int) -> Bool {
        (minMinutes...maxMinutes).contains(minutes)
    }

    /// Reads a length typed by a person (`" 45 "`): the minutes, or nil if it isn't a whole number from 1 to 180.
    public static func parse(minutes text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), isValid(minutes: value) else { return nil }
        return value
    }

    /// The whole length in seconds.
    public var total: TimeInterval { TimeInterval(minutes * 60) }

    // MARK: - What it looks like

    public var isIdle: Bool { phase == .idle }
    public var isFinished: Bool { phase == .finished }
    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }
    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }
    /// Running or paused: the states that are remembered between launches.
    public var isActive: Bool { isRunning || isPaused }

    /// Seconds left at `now`: the full length when idle, the end minus now when
    /// running, what was left when paused, 0 when finished. Never negative, and
    /// never more than the length (a clock set backwards can't make time grow).
    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: return total
        case .running(let end): return min(max(0, end.timeIntervalSince(now)), total)
        case .paused(let remaining): return min(max(0, remaining), total)
        case .finished: return 0
        }
    }

    /// How much of the ring is left, from 1 (full) down to 0.
    public func fraction(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return remaining(at: now) / total
    }

    // MARK: - Changes

    /// Chooses the length. Only while idle, and only 1 to 180 minutes. Returns whether it changed.
    @discardableResult
    public mutating func setLength(minutes: Int) -> Bool {
        guard isIdle, Self.isValid(minutes: minutes) else { return false }
        self.minutes = minutes
        return true
    }

    /// Chooses the task. Only while idle.
    @discardableResult
    public mutating func setTask(_ id: String?) -> Bool {
        guard isIdle else { return false }
        taskID = id
        return true
    }

    /// Starts from idle: the end is now plus the length.
    @discardableResult
    public mutating func start(at now: Date) -> Bool {
        guard isIdle else { return false }
        phase = .running(end: now.addingTimeInterval(total))
        return true
    }

    /// Pauses a running session, keeping what is left. A session that has
    /// already run out finishes instead of pausing.
    @discardableResult
    public mutating func pause(at now: Date) -> Bool {
        guard case .running(let end) = phase else { return false }
        if end <= now {
            phase = .finished
            return false
        }
        phase = .paused(remaining: min(end.timeIntervalSince(now), total))
        return true
    }

    /// Continues a paused session: the end is now plus what was left.
    @discardableResult
    public mutating func resume(at now: Date) -> Bool {
        guard case .paused(let remaining) = phase else { return false }
        phase = .running(end: now.addingTimeInterval(remaining))
        return true
    }

    /// Back to idle (any state), keeping the length and the task.
    public mutating func reset() {
        phase = .idle
    }

    /// "Another one": from a finished session, start again with the same length and task.
    @discardableResult
    public mutating func restart(at now: Date) -> Bool {
        guard isFinished else { return false }
        phase = .idle
        return start(at: now)
    }

    /// Notices that the time has run out: a running session whose end has
    /// come (exactly at zero counts) becomes finished. Returns whether it did.
    /// Call it whenever the time may have passed: on a timer, and after waking up.
    @discardableResult
    public mutating func updateFinished(at now: Date) -> Bool {
        guard case .running(let end) = phase, end <= now else { return false }
        phase = .finished
        return true
    }

    // MARK: - Remembering it between launches

    /// The session as JSON, for the settings. Nil for an idle session: nothing to remember.
    public func encoded() -> Data? {
        guard !isIdle else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    /// Reads a remembered session and brings it up to `now`:
    /// - running with the end still ahead: running on;
    /// - running whose end has passed (the app was closed): finished;
    /// - paused: paused with what was left;
    /// - finished: finished.
    /// Nil if the data is unreadable or makes no sense (a length outside 1 to 180, a
    /// pause with no time left or more than the length): better no session than a wrong one.
    public static func restored(from data: Data, at now: Date) -> FocusSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var session = try? decoder.decode(FocusSession.self, from: data), isValid(minutes: session.minutes) else { return nil }
        switch session.phase {
        case .idle:
            return nil
        case .paused(let remaining):
            guard remaining > 0, remaining <= session.total else { return nil }
        case .running, .finished:
            break
        }
        // An end further away than the whole length can't be right (a clock that was far ahead when saved).
        if case .running(let end) = session.phase, end > now.addingTimeInterval(session.total) {
            session.phase = .running(end: now.addingTimeInterval(session.total))
        }
        session.updateFinished(at: now)
        return session
    }

    // MARK: - Words

    /// `24:31`, or `1:05:00` from an hour up. Rounded up to a whole second, so the
    /// display reads 0:01 until the very end and never shows 0:00 while running.
    public static func format(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Which task

/// What the task picker is set to.
public enum FocusTaskChoice: Equatable, Sendable {
    /// Not chosen yet: the focus card if there is one, else the first Today card.
    case automatic
    /// "No task, just focus".
    case none
    case task(String)

    /// The task a session would be linked to, from the Today cards (in order).
    /// A chosen task that has left Today (finished, moved) falls back to the default.
    public func resolve(today: [BoardTask]) -> String? {
        let automatic = today.first(where: \.focus)?.id ?? today.first?.id
        switch self {
        case .automatic: return automatic
        case .none: return nil
        case .task(let id): return today.contains { $0.id == id } ? id : automatic
        }
    }
}
