// One file in the Inbox, read back (spec 3): what was typed, when, and what
// became of it.

import Foundation

/// What became of a capture (spec 3). The raw value is what's written in the
/// file's `outcome:` field.
public enum InboxOutcome: String, Sendable, CaseIterable {
    case taskSuggested = "task-suggested"
    case noteFiled = "note-filed"
    case answered
    case waitingForAnswer = "waiting-for-answer"
    case skipped
}

public struct InboxEntry: Equatable, Sendable {
    /// The file name.
    public var id: String
    /// Exactly what was typed.
    public var text: String
    /// `YYYY-MM-DDTHH:MM`, local time (like `created` in a task). Nil if the file has none.
    public var captured: String?
    /// Nil means nothing has happened to it yet.
    public var outcome: InboxOutcome?

    public init(id: String, text: String, captured: String? = nil, outcome: InboxOutcome? = nil) {
        self.id = id
        self.text = text
        self.captured = captured
        self.outcome = outcome
    }

    /// Reads a file's text. This never fails: a file without frontmatter
    /// (someone dropped a plain note in the Inbox) is an entry whose text is
    /// the whole file; broken frontmatter just means no fields.
    public static func parse(id: String, text: String) -> InboxEntry {
        let (yaml, body) = splitFrontmatter(text)
        // `try?` turns "this can throw" into "nil if it did".
        let fields = (try? Frontmatter.parse(yaml ?? "")) ?? Frontmatter()
        return InboxEntry(
            id: id, text: body, captured: fieldText(fields["captured"]),
            // An unknown outcome is read as missing (spec 3).
            outcome: fieldText(fields["outcome"]).flatMap { InboxOutcome(rawValue: $0) })
    }

    /// The file text with its `outcome:` set, for recording what happened.
    /// Only the frontmatter changes: `outcome` is added or replaced, other
    /// fields keep their place and the body stays byte for byte as it was.
    /// Returns nil if the frontmatter is broken (don't overwrite what we
    /// can't read, like saving a task, task format 5.1).
    public static func settingOutcome(_ outcome: InboxOutcome, in fileText: String) -> String? {
        let (yaml, body) = splitFrontmatter(fileText)
        guard var fields = try? Frontmatter.parse(yaml ?? ""), let rendered = { () -> String? in
            fields.set("outcome", stringNode(outcome.rawValue))
            return try? fields.render()
        }() else { return nil }
        return "---\n" + rendered + "---\n" + body
    }
}
