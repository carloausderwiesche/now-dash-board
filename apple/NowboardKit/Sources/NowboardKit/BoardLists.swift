// The lists the board shows, worked out from all tasks: the Swift version
// of the sorting in src/board.ts. Pure: it doesn't touch files or the UI.

import Foundation

/// What the board shows, worked out from all tasks. A value, so the view
/// just reads it; nothing here changes a file.
public struct BoardLists: Equatable, Sendable {
    /// Today's cards in order, the focus card among them (it's drawn twice as
    /// wide where it is, like the Tauri app).
    public var today: [BoardTask] = []
    public var suggested: [BoardTask] = []
    public var backlog: [BoardTask] = []
    /// Finished today, newest first.
    public var doneToday: [BoardTask] = []
    /// Finished since `recentSince` (the last 7 days), newest first: the list
    /// under the Done number.
    public var doneRecent: [BoardTask] = []

    /// `today` is "YYYY-MM-DD", the day to count Done for; `recentSince` the
    /// first day of the Done list (defaults to `today`).
    public init(tasks: [BoardTask], today day: String, recentSince: String? = nil) {
        // Sorted by order, then title (spec 4.4). `sorted(by:)` takes a closure:
        // a small function written inline, `{ a, b in … }`.
        let sorted = tasks.sorted { a, b in
            let (x, y) = (a.order ?? 0, b.order ?? 0)
            return x != y ? x < y : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        today = sorted.filter { $0.status == .today }
        suggested = sorted.filter { $0.status == .suggested }
        backlog = sorted.filter { $0.status == .backlog }
        // Timestamps sort as text: "2026-11-24T15:30" > "2026-11-24T09:00".
        let done = sorted.filter { $0.status == .done }.sorted { ($0.done ?? "") > ($1.done ?? "") }
        doneToday = done.filter { ($0.done ?? "").hasPrefix(day) }
        let since = recentSince ?? day
        doneRecent = done.filter { ($0.done ?? "") >= since }
    }
}
