// The lists the board shows, worked out from all tasks: the Swift version
// of the sorting in src/board.ts. Pure: it doesn't touch files or the UI.

import Foundation

/// What the board shows, worked out from all tasks. A value, so the view
/// just reads it; nothing here changes a file.
public struct BoardLists: Equatable, Sendable {
    public var focus: BoardTask?
    public var today: [BoardTask] = []
    public var suggested: [BoardTask] = []
    public var backlog: [BoardTask] = []
    /// Finished today, newest first.
    public var doneToday: [BoardTask] = []

    /// `today` is "YYYY-MM-DD", the day to count Done for.
    public init(tasks: [BoardTask], today day: String) {
        // Sorted by order, then title (spec 4.4). `sorted(by:)` takes a closure:
        // a small function written inline, `{ a, b in … }`.
        let sorted = tasks.sorted { a, b in
            let (x, y) = (a.order ?? 0, b.order ?? 0)
            return x != y ? x < y : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        let todays = sorted.filter { $0.status == .today }
        focus = todays.first { $0.focus }
        today = todays.filter { $0.id != focus?.id }
        suggested = sorted.filter { $0.status == .suggested }
        backlog = sorted.filter { $0.status == .backlog }
        doneToday = sorted.filter { $0.status == .done && ($0.done ?? "").hasPrefix(day) }
            .sorted { ($0.done ?? "") > ($1.done ?? "") }
    }
}
