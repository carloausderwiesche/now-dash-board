// The card grid, laid out the way the Tauri app's CSS grid does it:
// `grid-template-columns: repeat(auto-fill, minmax(200px, 1fr))`.
// As many columns of at least `minWidth` as fit, sharing the width evenly;
// cards go in order, row by row; each row is as tall as its tallest card and
// every card in it stretches to that height. A card can span two columns
// (the focus card); if it doesn't fit at the end of a row, it starts the next.
//
// SwiftUI's own LazyVGrid can't span columns, so this is a custom `Layout`:
// SwiftUI asks it for its size (`sizeThatFits`) and then where to put each
// child (`placeSubviews`).

import SwiftUI

/// How many columns a card takes. Set with `.gridSpan(2)`.
private struct GridSpan: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    func gridSpan(_ n: Int) -> some View {
        layoutValue(key: GridSpan.self, value: n)
    }
}

struct CardGridLayout: Layout {
    var minWidth: CGFloat
    var spacing: CGFloat

    /// Where every card goes, for a given width. Both methods below use it.
    private func plan(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let columns = max(1, Int((width + spacing) / (minWidth + spacing)))
        let cell = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        // 1. Put each card in a row and column, like CSS grid without "dense".
        var slots: [(row: Int, column: Int, span: Int)] = []
        var row = 0, column = 0
        for view in subviews {
            let span = min(view[GridSpan.self], columns)
            if column + span > columns {
                row += 1
                column = 0
            }
            slots.append((row, column, span))
            column += span
            if column == columns {
                row += 1
                column = 0
            }
        }

        // 2. Each row is as tall as its tallest card at that card's width.
        let rowCount = (slots.map(\.row).max() ?? -1) + 1
        var rowHeights = Array(repeating: CGFloat(0), count: rowCount)
        for (view, slot) in zip(subviews, slots) {
            let w = cell * CGFloat(slot.span) + spacing * CGFloat(slot.span - 1)
            let h = view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            rowHeights[slot.row] = max(rowHeights[slot.row], h)
        }

        // 3. Frames, row by row.
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for h in rowHeights {
            tops.append(y)
            y += h + spacing
        }
        let frames = slots.map { slot in
            CGRect(
                x: (cell + spacing) * CGFloat(slot.column),
                y: tops[slot.row],
                width: cell * CGFloat(slot.span) + spacing * CGFloat(slot.span - 1),
                height: rowHeights[slot.row])
        }
        return (frames, max(0, y - spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        return CGSize(width: width, height: plan(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = plan(width: bounds.width, subviews: subviews).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
