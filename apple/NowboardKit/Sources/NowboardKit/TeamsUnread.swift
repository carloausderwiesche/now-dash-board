// The unread count of Microsoft Teams, read from its Dock badge: reading the
// text, and what the dashboard says about it. Pure rules only: how the text is
// fetched from the Dock (the Accessibility interface) is the app's job, so
// everything here can be tested with plain strings.

import Foundation

/// How many messages are unread, as far as the Dock badge says.
public enum UnreadCount: Equatable, Sendable {
    /// Nothing unread.
    case none
    /// Exactly this many.
    case count(Int)
    /// This many or more (the badge says `99+`).
    case atLeast(Int)
    /// Something is unread but the badge doesn't say how much (a dot, or text we don't know).
    case unknown

    /// Reads a Dock badge label (the `AXStatusLabel` text):
    /// - missing, empty or `0`: nothing unread;
    /// - `3`: three; `1,234` or `1 234` (thousands separators): that number;
    /// - `99+`: 99 or more;
    /// - a dot (`•`, `●`) or any other text: unread, count unknown.
    ///
    /// Swift note: this is a pure function: the same text always gives the same
    /// answer, and nothing else is touched, so it is easy to test.
    public static func parse(_ label: String?) -> UnreadCount {
        guard let label else { return .none }
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .none }

        // `99+`: a number and a plus.
        if text.hasSuffix("+"), let n = number(String(text.dropLast())) {
            return n > 0 ? .atLeast(n) : .unknown
        }
        if let n = number(text) {
            return n == 0 ? .none : .count(n)
        }
        return .unknown
    }

    /// A whole number: plain digits, or digits in groups of three with a separator between
    /// the groups (`1,234`, `1.234`, `1 234`). So `1.5`, `1,5` and `.5` are NOT numbers
    /// (they'd be a decimal, not 15 or 5). Nil for anything else, including negative numbers,
    /// look-alike digits and numbers too big for an `Int`.
    ///
    /// Swift note: `/…/` is a regular expression; `wholeMatch` must match the whole text.
    private static func number(_ text: String) -> Int? {
        let plain = text.wholeMatch(of: /[0-9]+/) != nil
        let grouped = text.wholeMatch(of: /[0-9]{1,3}([.,\u{00A0}\u{202F} ][0-9]{3})+/) != nil
        guard plain || grouped else { return nil }
        return Int(text.filter { $0 >= "0" && $0 <= "9" })
    }

    /// Whether anything is unread.
    public var hasUnread: Bool { self != .none }
}

/// What the Teams box on the dashboard knows.
public enum TeamsStatus: Equatable, Sendable {
    /// Teams isn't running: unavailable, which is not the same as "0 unread".
    case notRunning
    /// Teams runs but has no item in the Dock (the person removed it, or it's hidden): there is no badge to read.
    case notInDock
    /// Nowboard isn't allowed to use the Accessibility interface (the person hasn't granted it).
    case notAllowed
    case unread(UnreadCount)
}

/// The words for the Teams box: a big part and a small part, and whether it
/// should look muted (nothing to see, or not available).
public struct TeamsDisplay: Equatable, Sendable {
    /// The big text: `3`, `99+`, `•`, `0`, or `—`.
    public var headline: String
    /// The small text next to it.
    public var detail: String
    /// Greyed out: nothing unread, or no reading at all.
    public var muted: Bool
    /// The box should offer "Allow access".
    public var needsPermission: Bool

    public init(_ status: TeamsStatus) {
        switch status {
        case .notRunning:
            self = TeamsDisplay(headline: "—", detail: "Teams isn't running", muted: true, needsPermission: false)
        case .notInDock:
            self = TeamsDisplay(headline: "—", detail: "Teams has no Dock icon, so its badge can't be read", muted: true, needsPermission: false)
        case .notAllowed:
            self = TeamsDisplay(
                headline: "—", detail: "Nowboard isn't allowed to read the Dock badge yet", muted: true, needsPermission: true)
        case .unread(.none):
            self = TeamsDisplay(headline: "0", detail: "Nothing unread", muted: true, needsPermission: false)
        case .unread(.count(let n)):
            self = TeamsDisplay(headline: String(n), detail: "unread", muted: false, needsPermission: false)
        case .unread(.atLeast(let n)):
            self = TeamsDisplay(headline: "\(n)+", detail: "unread", muted: false, needsPermission: false)
        case .unread(.unknown):
            self = TeamsDisplay(headline: "•", detail: "Unread messages, count unknown", muted: false, needsPermission: false)
        }
    }

    private init(headline: String, detail: String, muted: Bool, needsPermission: Bool) {
        self.headline = headline
        self.detail = detail
        self.muted = muted
        self.needsPermission = needsPermission
    }
}

/// What reading the Dock gave (the app fills this in).
public enum DockBadgeReading: Equatable, Sendable {
    case notAllowed
    case notRunning
    case notInDock
    /// Teams is running; this is its badge text (nil = no badge).
    case label(String?)
    /// The Dock didn't answer properly this time (busy, restarting). That says nothing about
    /// Teams: the box keeps what it showed before instead of guessing.
    case failed

    /// The status the box shows for this reading, or nil for "no answer this time".
    public var status: TeamsStatus? {
        switch self {
        case .notAllowed: .notAllowed
        case .notRunning: .notRunning
        case .notInDock: .notInDock
        case .label(let text): .unread(UnreadCount.parse(text))
        case .failed: nil
        }
    }
}
