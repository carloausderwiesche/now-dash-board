// The same dropPreview cases as src/useDnd.test.ts, plus the grid geometry.

import CoreGraphics
import Testing

@testable import NowboardKit

private let list = ["a", "b", "c"]

@Test func showsNothingWhileTheCardPointsAtItsOwnSlot() {
    #expect(DropRules.preview(ids: list, dragged: "b", before: "b") == nil)
    #expect(DropRules.preview(ids: list, dragged: "b", before: "c") == nil)  // just below itself
    #expect(DropRules.preview(ids: list, dragged: "c", before: nil) == nil)  // last card to the end
}

@Test func closesItsOwnSlotWhenMovingElsewhereInItsList() {
    #expect(DropRules.preview(ids: list, dragged: "c", before: "a")! == (0, true))
    #expect(DropRules.preview(ids: list, dragged: "a", before: nil)! == (3, true))
}

@Test func onlyOpensAGapWhenComingFromAnotherList() {
    #expect(DropRules.preview(ids: list, dragged: "x", before: "b")! == (1, false))
    #expect(DropRules.preview(ids: [], dragged: "x", before: nil)! == (0, false))
}

@Test func showsNothingForACardThatIsNotInTheList() {
    #expect(DropRules.preview(ids: list, dragged: "x", before: "gone") == nil)
}

// A 3-column grid at (0, 100), 100pt cells, 10pt gaps, two rows of cards.
private let grid = CGRect(x: 0, y: 100, width: 320, height: 210)
private func card(_ id: String, _ col: Int, _ row: Int, span: Int = 1) -> PlacedCard {
    PlacedCard(id: id, frame: CGRect(x: CGFloat(col) * 110, y: 100 + CGFloat(row) * 110, width: CGFloat(span) * 100 + CGFloat(span - 1) * 10, height: 100), span: span)
}
private let cards = [card("a", 0, 0), card("b", 1, 0), card("c", 2, 0), card("d", 0, 1)]

private func spot(_ x: CGFloat, _ y: CGFloat, dragged: String = "x", cards: [PlacedCard] = cards) -> DropTarget? {
    DropRules.spot(in: grid, status: .today, point: CGPoint(x: x, y: y), cards: cards, dragged: dragged,
                   columns: 3, spacing: 10, ghostSpan: 1)
}

@Test func theSpotIsTheCellUnderThePointer() {
    #expect(spot(150, 150) == DropTarget(status: .today, beforeID: "b"))
    #expect(spot(50, 260) == DropTarget(status: .today, beforeID: "d"))
    #expect(spot(160, 260) == DropTarget(status: .today, beforeID: nil))  // past the last card
}

@Test func theDraggedCardDoesNotCountWhenFindingTheSpot() {
    // Dragging "a": the others close up, so the first cell is now before "b".
    #expect(spot(50, 150, dragged: "a") == DropTarget(status: .today, beforeID: "b"))
}

@Test func zonesFollowEachOtherWithoutGaps() {
    let zones = [
        DropZone(status: .today, frame: CGRect(x: 0, y: 0, width: 300, height: 300), grid: CGRect(x: 0, y: 50, width: 300, height: 250)),
        DropZone(status: .backlog, frame: CGRect(x: 0, y: 340, width: 300, height: 300), grid: CGRect(x: 0, y: 390, width: 300, height: 250)),
        DropZone(status: .done, frame: CGRect(x: 0, y: 680, width: 300, height: 80), grid: nil),
    ]
    #expect(DropRules.zone(at: 360, in: zones)?.status == .today)  // the Backlog heading still counts as Today
    #expect(DropRules.zone(at: 400, in: zones)?.status == .backlog)
    #expect(DropRules.zone(at: 700, in: zones)?.status == .done)
    #expect(DropRules.zone(at: 2000, in: zones) == nil)
}

@Test func columnsLikeCSSAutoFill() {
    #expect(DropRules.columns(width: 784, minWidth: 200, spacing: 12) == 3)
    #expect(DropRules.columns(width: 784, minWidth: 180, spacing: 10) == 4)
    #expect(DropRules.columns(width: 150, minWidth: 200, spacing: 12) == 1)
}

@Test func cardsMustBeInReadingOrder() {
    // The rule relies on reading order: the app sorts its measured frames first.
    // With the cards shuffled, the same pointer would pick a different neighbour.
    let shuffled = [cards[3], cards[1], cards[0], cards[2]]
    #expect(spot(50, 150, cards: shuffled) != DropTarget(status: .today, beforeID: "a"))
    #expect(spot(50, 150) == DropTarget(status: .today, beforeID: "a"))
}

@Test func anUnlimitedOrBrokenWidthIsOneColumnNotACrash() {
    // SwiftUI can offer an infinite width while measuring (the Dashboard's Today grid did).
    #expect(DropRules.columns(width: .infinity, minWidth: 200, spacing: 12) == 1)
    #expect(DropRules.columns(width: -.infinity, minWidth: 200, spacing: 12) == 1)
    #expect(DropRules.columns(width: .nan, minWidth: 200, spacing: 12) == 1)
    #expect(DropRules.columns(width: 0, minWidth: 200, spacing: 12) == 1)
    #expect(DropRules.columns(width: -50, minWidth: 200, spacing: 12) == 1)
}
