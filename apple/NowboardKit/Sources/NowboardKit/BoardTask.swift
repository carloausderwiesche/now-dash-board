// The task model: what a task file means once it's read.
// The rules for reading and writing it are in docs/task-format.md.
//
// Swift note: `struct` is a value type. Copying a struct copies its data, so
// changing a copy never changes the original (unlike a `class`). `Sendable`
// promises it's safe to pass between threads, which Swift 6 checks for us.
// `Equatable` lets tests compare two tasks with `==`; `Codable` lets them be
// turned into and from JSON.

/// Which list a task is in. A missing or unknown `status:` becomes `.backlog`.
///
/// Swift note: `String` after the colon gives each case a raw text value
/// (`TaskStatus.today.rawValue == "today"`), and `TaskStatus(rawValue: "x")`
/// gives `nil` for text that isn't a case.
public enum TaskStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case today, backlog, done, suggested
}

/// One line of the checklist: `- [ ] text` or `- [x] text`.
public struct ChecklistItem: Sendable, Equatable, Codable {
    public var text: String
    public var done: Bool

    public init(text: String, done: Bool) {
        self.text = text
        self.done = done
    }
}

/// One task, one file. Called `BoardTask`, not `Task`, because Swift already
/// has a `Task` type (for running work in the background), and two types with
/// the same name would be confusing everywhere.
public struct BoardTask: Sendable, Equatable {
    /// The file name inside the Tasks folder, e.g. `Fix k6 nightly token.md`.
    /// Empty for a task that hasn't been saved yet.
    public var id: String
    /// The file name without `.md`, or the full title from `title:` when the
    /// file name had to be shortened. For a new task: the title to name the file after.
    public var title: String
    public var status: TaskStatus
    /// Category id, e.g. "work". It's the card's colour.
    public var area: String
    /// The one card you're working on.
    public var focus: Bool
    /// Position within its list; smaller = higher. `nil` = the file has no
    /// `order` (yet); `TaskFolder.loadAll` gives it one (spec 4.2).
    ///
    /// Swift note: `Double?` means "a Double or nothing". Rust used NaN for
    /// this; an optional says it more plainly.
    public var order: Double?
    public var created: String?
    /// When it was finished (`done:` in the file).
    public var done: String?
    public var project: String?
    public var from: String?
    /// `#private` appears somewhere in the body. Computed when reading.
    public var isPrivate: Bool
    public var items: [ChecklistItem]
    public var notes: String

    /// A new, unsaved task. Every field has a default, so callers only name
    /// what they need: `BoardTask(title: "Buy milk", status: .today)`.
    public init(
        id: String = "",
        title: String,
        status: TaskStatus = .backlog,
        area: String = "personal",
        focus: Bool = false,
        order: Double? = nil,
        created: String? = nil,
        done: String? = nil,
        project: String? = nil,
        from: String? = nil,
        isPrivate: Bool = false,
        items: [ChecklistItem] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.area = area
        self.focus = focus
        self.order = order
        self.created = created
        self.done = done
        self.project = project
        self.from = from
        self.isPrivate = isPrivate
        self.items = items
        self.notes = notes
    }
}
