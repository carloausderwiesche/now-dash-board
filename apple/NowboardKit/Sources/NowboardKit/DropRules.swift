// Where a dragged card lands: the Swift version of `zoneAt`, `spotIn` and
// `dropPreview` in src/useDnd.ts. Pure geometry: the app measures where the
// sections and cards are, these functions decide; the app then draws.

import CoreGraphics
import Foundation

/// A drop spot: a list, and the card the dropped one goes before (nil = at the end).
public struct DropTarget: Equatable, Sendable {
    public var status: TaskStatus
    public var beforeID: String?

    public init(status: TaskStatus, beforeID: String? = nil) {
        self.status = status
        self.beforeID = beforeID
    }
}

/// A list on the board, as measured on screen.
public struct DropZone: Sendable {
    public var status: TaskStatus
    /// The whole section (heading included).
    public var frame: CGRect
    /// Its card grid, if it shows cards.
    public var grid: CGRect?

    public init(status: TaskStatus, frame: CGRect, grid: CGRect?) {
        self.status = status
        self.frame = frame
        self.grid = grid
    }
}

/// A card in a grid, as measured on screen.
public struct PlacedCard: Sendable {
    public var id: String
    public var frame: CGRect
    /// Columns it takes (the focus card: 2).
    public var span: Int

    public init(id: String, frame: CGRect, span: Int) {
        self.id = id
        self.frame = frame
        self.span = span
    }
}

public enum DropRules {
    /// Which list's area is at height `y` (zones in board order: Today, Backlog, Done).
    /// The areas follow each other with no gaps: each starts where its cards
    /// start and runs to where the next list's cards start, so the space under
    /// Today, the Suggested strip and the Backlog heading all count as Today.
    public static func zone(at y: CGFloat, in zones: [DropZone]) -> DropZone? {
        let tops = zones.enumerated().map { i, z in
            i == 0 || z.grid == nil ? z.frame.minY : z.grid!.minY - 8
        }
        for (i, z) in zones.enumerated() {
            let bottom = i + 1 < zones.count ? tops[i + 1] : z.frame.maxY + 120
            if y >= tops[i] && y < bottom { return z }
        }
        return nil
    }

    /// How many columns a grid of `width` has (the CardGridLayout / CSS auto-fill rule).
    public static func columns(width: CGFloat, minWidth: CGFloat, spacing: CGFloat) -> Int {
        let fit = (width + spacing) / (minWidth + spacing)
        // `Int(x)` crashes for infinity and NaN. A layout can be offered an
        // unlimited width while SwiftUI measures it: one column then.
        guard fit.isFinite else { return 1 }
        return max(1, Int(fit))
    }

    /// The drop spot in a grid under the pointer, or nil to keep the current one.
    ///
    /// Works in grid *cells*: find the cell under the pointer, then pick the
    /// position at which the preview itself would sit in exactly that cell.
    /// The preview then lands under the pointer, so the next check gives the
    /// same answer and it can't flip back and forth at row ends.
    ///
    /// `cards` are the cards shown in the grid (including the dragged one and
    /// the preview), `columns` its column count, `ghostSpan` the preview's width.
    public static func spot(
        in grid: CGRect, status: TaskStatus, point: CGPoint, cards: [PlacedCard], dragged: String,
        columns cols: Int, spacing: CGFloat, ghostSpan: Int
    ) -> DropTarget? {
        let cell = (grid.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let px = point.x - grid.minX, py = point.y - grid.minY

        // Column under the pointer (each column owns half the gap on either side).
        var col = cols - 1
        for i in 0..<cols where px < CGFloat(i) * (cell + spacing) + cell + spacing / 2 {
            col = i
            break
        }
        // Row under the pointer, from where the cards sit.
        var bottoms: [CGFloat: CGFloat] = [:]
        for c in cards {
            let top = c.frame.minY - grid.minY
            bottoms[top] = max(bottoms[top] ?? 0, c.frame.maxY - grid.minY)
        }
        let rowBottoms = bottoms.keys.sorted().map { bottoms[$0]! }
        let row = rowBottoms.firstIndex { py < $0 + spacing / 2 } ?? rowBottoms.count
        let target = row * cols + col

        // The list without the dragged card and the preview, in order.
        let rest = cards.filter { $0.id != dragged && $0.id != ghostID }
        let spans = rest.map { min($0.span, cols) }
        let ghost = min(ghostSpan, cols)

        // Lay the cards out like CSS grid, with the preview at position p,
        // and return the cell where the preview starts.
        func previewCell(_ p: Int) -> Int {
            var r = 0, c = 0
            func place(_ span: Int) -> Int {
                if span > cols - c {
                    r += 1
                    c = 0
                }
                let start = r * cols + c
                c += span
                if c >= cols {
                    r += 1
                    c = 0
                }
                return start
            }
            for i in 0..<p { _ = place(spans[i]) }
            return place(ghost)
        }
        for p in 0...rest.count {
            let start = previewCell(p)
            if target >= start && target < start + ghost {
                return DropTarget(status: status, beforeID: p < rest.count ? rest[p].id : nil)
            }
        }
        // Past the last card: at the end. Otherwise (a gap left by a wide card): keep.
        return target > previewCell(rest.count) ? DropTarget(status: status) : nil
    }

    /// The id the drop preview ("ghost") uses in a list.
    public static let ghostID = "__ghost__"

    /// Where the preview goes in one list (`ids` = its cards in order), or
    /// nil for none. Inside its own list the card's own slot *is* the preview
    /// (it just fades), so nothing moves until you point somewhere else; then
    /// that slot closes (`collapse`) and the preview opens at `index`.
    public static func preview(ids: [String], dragged: String, before: String?) -> (index: Int, collapse: Bool)? {
        guard let at = before.map({ ids.firstIndex(of: $0) }) ?? ids.count else { return nil }
        let from = ids.firstIndex(of: dragged)
        if let from, at == from || at == from + 1 { return nil }
        return (at, from != nil)
    }
}
