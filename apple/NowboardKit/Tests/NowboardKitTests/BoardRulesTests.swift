// The same cases as src/board.test.ts, so both apps move cards the same way.

import Testing

@testable import NowboardKit

private func task(_ id: String, _ status: TaskStatus, _ order: Double, focus: Bool = false, done: String? = nil) -> BoardTask {
    BoardTask(id: id, title: id, status: status, area: "work", focus: focus, order: order, done: done)
}

private let board = [task("a", .today, 1024), task("b", .today, 2048), task("c", .backlog, 1024)]

@Test func movesHalfwayBetweenNeighboursAndChangesOnlyThatCard() {
    let changed = BoardRules.planMove(board, id: "c", to: .today, before: "b")
    #expect(changed.map(\.id) == ["c"])
    #expect(changed[0].status == .today && changed[0].order == 1536)
}

@Test func goesOneStepAboveTheFirstOrBelowTheLast() {
    #expect(BoardRules.planMove(board, id: "c", to: .today, before: "a")[0].order == 1024 - BoardRules.step)
    #expect(BoardRules.planMove(board, id: "c", to: .today)[0].order == 2048 + BoardRules.step)
}

@Test func getsOrderZeroInAnEmptyList() {
    #expect(BoardRules.planMove(board, id: "a", to: .suggested)[0].order == 0)
}

@Test func endsFocusOutsideTodayAndClearsDoneOutsideDone() {
    #expect(BoardRules.planMove([task("f", .today, 1, focus: true)], id: "f", to: .backlog)[0].focus == false)
    let done = task("d", .done, 1, done: "2026-11-22T09:40")
    #expect(BoardRules.planMove([done], id: "d", to: .today)[0].done == nil)
    #expect(BoardRules.planMove([done, task("e", .done, 5)], id: "d", to: .done)[0].done == "2026-11-22T09:40")
}

@Test func spacesTheListOutWhenNeighboursShareAnOrder() {
    let tied = [task("a", .today, 7), task("b", .today, 7), task("c", .backlog, 1)]
    let changed = BoardRules.planMove(tied, id: "c", to: .today, before: "b")
    #expect(changed.map(\.id) == ["a", "c", "b"])
    #expect(changed.map(\.order) == [1024, 2048, 3072])
}

@Test func changesNothingForAnUnknownCardOrADropOntoItself() {
    #expect(BoardRules.planMove(board, id: "nope", to: .today).isEmpty)
    #expect(BoardRules.planMove(board, id: "a", to: .today, before: "a").isEmpty)
}

@Test func topOrderIsOneStepAboveTheSmallest() {
    #expect(BoardRules.topOrder([task("a", .today, 300), task("b", .today, 100)], .today) == 100 - BoardRules.step)
    #expect(BoardRules.topOrder([task("a", .today, 300)], .backlog) == 0)
}

@Test func nextAreaWrapsAround() {
    #expect(BoardRules.nextArea(after: "work", in: ["personal", "work", "freelance"]) == "freelance")
    #expect(BoardRules.nextArea(after: "freelance", in: ["personal", "work", "freelance"]) == "personal")
    #expect(BoardRules.nextArea(after: "gone", in: ["personal", "work"]) == "personal")
}
