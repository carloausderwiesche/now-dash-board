// Moving cards around: the Swift version of `planMove` and `topOrder` in
// src/board.ts (spec 4.4). Pure functions: they say what changes, the store
// writes it.

import Foundation

public enum BoardRules {
    /// The gap between orders: new tasks go 1024 above the top one.
    public static let step: Double = 1024

    /// The order that puts a card on top of `status`.
    public static func topOrder(_ all: [BoardTask], _ status: TaskStatus) -> Double {
        let orders = all.filter { $0.status == status }.compactMap(\.order)
        return orders.min().map { $0 - step } ?? 0
    }

    /// Moves a card into `status`, before `beforeID` (or at the end), and
    /// returns every task that changed: usually just the moved one, or none
    /// if nothing moves.
    ///
    /// Fractional ordering: the card gets the midpoint of its new neighbours'
    /// orders, so only its own file is rewritten. If the neighbours share an
    /// order (hand-written files), the whole list is numbered again, once.
    public static func planMove(_ all: [BoardTask], id: String, to status: TaskStatus, before beforeID: String? = nil) -> [BoardTask] {
        guard var moving = all.first(where: { $0.id == id }), id != beforeID else { return [] }
        let list = BoardLists.sorted(all.filter { $0.status == status && $0.id != id })
        var at = beforeID.flatMap { b in list.firstIndex { $0.id == b } } ?? list.count
        if at < 0 { at = list.count }
        let prev = at > 0 ? list[at - 1] : nil
        let next = at < list.count ? list[at] : nil
        let p = prev?.order ?? 0, n = next?.order ?? 0

        let order: Double =
            switch (prev, next) {
            case (.some, .some): (p + n) / 2
            case (nil, .some): n - step
            case (.some, nil): p + step
            case (nil, nil): 0
            }
        moving.order = order
        if status != .done { moving.done = nil }  // out of Done: no done time
        if status != .today { moving.focus = false }  // out of Today: no focus
        moving.status = status

        // No number between the neighbours: space the whole list out again.
        if prev != nil && next != nil && !(order > p && order < n) {
            var spaced = list
            spaced.insert(moving, at: at)
            return spaced.enumerated().map { i, t in
                var t = t
                t.order = Double(i + 1) * step
                return t
            }
        }
        return [moving]
    }

    /// The next category after `area`, wrapping around (tapping a card's dot).
    public static func nextArea(after area: String, in ids: [String]) -> String {
        guard !ids.isEmpty else { return area }
        let i = ids.firstIndex(of: area) ?? -1
        return ids[(i + 1) % ids.count]
    }
}
