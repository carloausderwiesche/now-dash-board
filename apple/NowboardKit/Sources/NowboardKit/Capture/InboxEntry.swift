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
    /// It's a question. Answering from the vault isn't built yet, so it
    /// waits, and nothing was filed (spec 3).
    case questionOpen = "question-open"
}

/// What to write into a raw capture's frontmatter: the outcome and the
/// extra fields that go with it. A field with a nil value is removed.
public struct InboxUpdate: Sendable, Equatable {
    public var outcome: InboxOutcome
    public var fields: [Field]

    public struct Field: Sendable, Equatable {
        public var key: String
        public var value: String?
        public init(_ key: String, _ value: String?) {
            self.key = key
            self.value = value
        }
    }

    public init(_ outcome: InboxOutcome, _ fields: [Field] = []) {
        self.outcome = outcome
        self.fields = fields
    }

    /// The fields only a filed result has. Every update that doesn't set them removes them.
    static let resultKeys = ["follow_up", "task", "note", "note_sha", "daily_note", "daily_line", "notice"]

    /// The same update with every result field that isn't mentioned removed.
    func clearingTheRest() -> InboxUpdate {
        var copy = self
        for key in Self.resultKeys where !fields.contains(where: { $0.key == key }) {
            copy.fields.append(Field(key, nil))
        }
        return copy
    }
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
    /// The question waiting for the person (`waiting-for-answer`).
    public var followUp: String?
    /// The task file the app made for it (`task-suggested`), a file name in the Tasks folder.
    public var taskFile: String?
    /// The note the app filed (`note-filed`), relative to the vault.
    public var notePath: String?
    /// A fingerprint of the note as the app wrote it, to know later if someone changed it.
    public var noteDigest: String?
    /// The daily note and the exact line the app added to it.
    public var dailyNote: String?
    public var dailyLine: String?
    /// Something the person should know: a folder that couldn't be used, a daily note that couldn't be updated.
    public var notice: String?

    public init(
        id: String, text: String, captured: String? = nil, outcome: InboxOutcome? = nil, followUp: String? = nil,
        taskFile: String? = nil, notePath: String? = nil, noteDigest: String? = nil, dailyNote: String? = nil,
        dailyLine: String? = nil, notice: String? = nil
    ) {
        self.id = id
        self.text = text
        self.captured = captured
        self.outcome = outcome
        self.followUp = followUp
        self.taskFile = taskFile
        self.notePath = notePath
        self.noteDigest = noteDigest
        self.dailyNote = dailyNote
        self.dailyLine = dailyLine
        self.notice = notice
    }

    /// Something the app made that Undo would take away again.
    public var hasFiledResult: Bool { taskFile != nil || notePath != nil }

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
            outcome: fieldText(fields["outcome"]).flatMap { InboxOutcome(rawValue: $0) },
            followUp: fieldText(fields["follow_up"]), taskFile: fieldText(fields["task"]), notePath: fieldText(fields["note"]),
            noteDigest: fieldText(fields["note_sha"]), dailyNote: fieldText(fields["daily_note"]),
            dailyLine: fieldText(fields["daily_line"]), notice: fieldText(fields["notice"]))
    }

    /// The file text with an update written into its frontmatter. Only the
    /// frontmatter changes: fields are added or replaced, other fields keep
    /// their place and the body stays byte for byte as it was. Returns nil if
    /// the frontmatter is broken (don't overwrite what we can't read, like
    /// saving a task, task format 5.1).
    public static func applying(_ update: InboxUpdate, to fileText: String) -> String? {
        let (yaml, body) = splitFrontmatter(fileText)
        guard var fields = try? Frontmatter.parse(yaml ?? "") else { return nil }
        fields.set("outcome", stringNode(update.outcome.rawValue))
        for field in update.fields {
            if let value = field.value { fields.set(field.key, stringNode(value)) } else { fields.remove(field.key) }
        }
        guard let rendered = try? fields.render() else { return nil }
        return "---\n" + rendered + "---\n" + body
    }

    /// The file text with its `outcome:` set, for recording what happened.
    public static func settingOutcome(_ outcome: InboxOutcome, in fileText: String) -> String? {
        applying(InboxUpdate(outcome), to: fileText)
    }

    /// For ordering: when it was captured, then the clash counter (`… (2).md`).
    /// File names alone sort wrongly: `… (2).md` would come before `….md`.
    var sortKey: (String, Int) {
        let stem = id.hasSuffix(".md") ? String(id.dropLast(3)) : id
        if let match = stem.wholeMatch(of: /(.*) \((\d+)\)/), let n = Int(match.2) { return (String(match.1), n) }
        return (stem, 1)
    }
}
