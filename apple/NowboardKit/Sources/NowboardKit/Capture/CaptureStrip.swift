// What the capture bar and the Inbox page say, decided by pure functions: the
// same input always gives the same text, so every case can be tested without
// a screen. The views only draw what these return.

import Foundation

// MARK: - The reply strip above the capture field

/// A finished capture the strip may mention for a few seconds.
public struct RecentCapture: Equatable, Sendable {
    public var entry: InboxEntry
    /// When it happened.
    public var at: Date
    /// The name of the category a suggested task landed in, if the app knows it.
    public var categoryName: String?

    public init(entry: InboxEntry, at: Date, categoryName: String? = nil) {
        self.entry = entry
        self.at = at
        self.categoryName = categoryName
    }
}

/// Everything the strip is decided from.
public struct CaptureStripInput: Equatable, Sendable {
    /// Captures being classified or waiting their turn.
    public var pending: Int
    /// The last error as a sentence, if the last action failed.
    public var problem: String?
    /// True if the last capture's text could not even be saved.
    public var textUnsaved: Bool
    /// The oldest capture waiting for an answer.
    public var openQuestion: InboxEntry?
    /// How many are waiting, the open one included.
    public var waitingCount: Int
    public var recent: RecentCapture?
    public var now: Date

    public init(
        pending: Int = 0, problem: String? = nil, textUnsaved: Bool = false, openQuestion: InboxEntry? = nil, waitingCount: Int = 0,
        recent: RecentCapture? = nil, now: Date = Date()
    ) {
        self.pending = pending
        self.problem = problem
        self.textUnsaved = textUnsaved
        self.openQuestion = openQuestion
        self.waitingCount = waitingCount
        self.recent = recent
        self.now = now
    }
}

/// What the strip shows. `nil` (no strip) is also an answer.
public enum CaptureStrip: Equatable, Sendable {
    /// "Sorting…": something is being classified.
    case sorting
    /// An error, in words. `textSaved` says whether the person's text is safe in the Inbox.
    case problem(message: String, textSaved: Bool)
    /// A question for the person, with Task / Note / Skip. `others` more are waiting behind it.
    case question(entryID: String, typed: String, question: String, others: Int)
    /// One line about what just happened, with Undo when the pipeline allows it.
    case result(entryID: String, message: String, canUndo: Bool)
    /// It was a question; answering those comes later. Honest about it.
    case questionLater(entryID: String, message: String)

    /// How long a result stays before it fades.
    public static let fadeAfter: TimeInterval = 8

    /// Decides what to show. In this order of importance: something is being
    /// sorted; an error; a question waiting for an answer; a result from the
    /// last few seconds; nothing.
    public static func decide(_ input: CaptureStripInput) -> CaptureStrip? {
        if input.pending > 0 { return .sorting }
        if let problem = input.problem { return .problem(message: problem, textSaved: !input.textUnsaved) }
        if let question = input.openQuestion {
            return .question(
                entryID: question.id, typed: question.text, question: question.followUp ?? CaptureResult.defaultQuestion,
                others: max(0, input.waitingCount - 1))
        }
        guard let recent = input.recent, input.now.timeIntervalSince(recent.at) < fadeAfter else { return nil }
        let entry = recent.entry
        switch entry.outcome {
        case .taskSuggested, .noteFiled:
            return .result(
                entryID: entry.id, message: InboxText.outcome(entry, categoryName: recent.categoryName), canUndo: entry.hasFiledResult)
        case .questionOpen:
            return .questionLater(entryID: entry.id, message: InboxText.outcome(entry, categoryName: nil))
        default:
            return nil
        }
    }
}

// MARK: - Words for an entry

public enum InboxText {
    /// What became of a capture, in words (the Inbox rows and the strip).
    public static func outcome(_ entry: InboxEntry, categoryName: String?) -> String {
        var text: String
        switch entry.outcome {
        case nil: text = "Not sorted yet"
        case .taskSuggested?:
            text = categoryName.map { "Task suggested in \($0)" } ?? "Task suggested"
        case .noteFiled?:
            text = "Note filed " + location(of: entry.notePath)
            if entry.dailyLine != nil { text += ", added to today's daily note" }
        case .answered?: text = "Answered"
        case .waitingForAnswer?: text = "Waiting for your answer"
        case .skipped?: text = "Skipped"
        case .questionOpen?: text = "A question. Answering questions comes in a later version, so it stays here."
        }
        if let notice = entry.notice { text += ". " + notice }
        return text
    }

    /// `under Wiki/Ideas` or `in the vault's top folder`.
    static func location(of notePath: String?) -> String {
        guard let notePath else { return "in the vault" }
        let folder = notePath.split(separator: "/").dropLast().joined(separator: "/")
        return folder.isEmpty ? "in the top folder of the vault" : "under \(folder)"
    }

    /// Whether Undo makes sense for an entry: something was filed for it.
    public static func canUndo(_ entry: InboxEntry) -> Bool { entry.hasFiledResult }
}

// MARK: - The Inbox page's list

public enum InboxList {
    /// The rows for the Inbox page: captures waiting for an answer first (the
    /// one asked first at the top, as the strip asks them), then everything
    /// else, newest first.
    public static func ordered(_ entries: [InboxEntry]) -> [InboxEntry] {
        let waiting = entries.filter { $0.outcome == .waitingForAnswer }.sorted { $0.sortKey < $1.sortKey }
        let rest = entries.filter { $0.outcome != .waitingForAnswer }.sorted { $0.sortKey > $1.sortKey }
        return waiting + rest
    }

    /// How many captures wait for an answer: the badge on the Inbox tab.
    public static func waitingCount(_ entries: [InboxEntry]) -> Int {
        entries.filter { $0.outcome == .waitingForAnswer }.count
    }

    /// The question to ask now: the oldest waiting capture.
    public static func openQuestion(_ entries: [InboxEntry]) -> InboxEntry? {
        entries.filter { $0.outcome == .waitingForAnswer }.min { $0.sortKey < $1.sortKey }
    }
}
