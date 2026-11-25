import Testing

@testable import NowboardKit

@Test func listsAreSortedByOrderThenTitle() {
    let lists = BoardLists(tasks: [
        BoardTask(id: "b.md", title: "b", status: .today, order: 2),
        BoardTask(id: "c.md", title: "c", status: .today, order: 1),
        BoardTask(id: "a.md", title: "a", status: .today, order: 2),
        BoardTask(id: "x.md", title: "x", status: .backlog, order: 5),
    ], today: "2026-11-24")
    #expect(lists.today.map(\.title) == ["c", "a", "b"])
    #expect(lists.backlog.map(\.title) == ["x"])
}

@Test func theFocusCardStaysInItsPlace() {
    let lists = BoardLists(tasks: [
        BoardTask(id: "a.md", title: "a", status: .today, order: 1),
        BoardTask(id: "b.md", title: "b", status: .today, focus: true, order: 2),
    ], today: "2026-11-24")
    #expect(lists.today.map(\.title) == ["a", "b"])
}

@Test func doneCountsOnlyTodayNewestFirst() {
    let lists = BoardLists(tasks: [
        BoardTask(id: "a.md", title: "a", status: .done, order: 1, done: "2026-11-24T09:00"),
        BoardTask(id: "b.md", title: "b", status: .done, order: 2, done: "2026-11-24T15:30"),
        BoardTask(id: "c.md", title: "c", status: .done, order: 3, done: "2026-11-23T18:00"),
        BoardTask(id: "d.md", title: "d", status: .done, order: 4),
    ], today: "2026-11-24")
    #expect(lists.doneToday.map(\.title) == ["b", "a"])
}

@Test func theDoneListGoesBackToTheGivenDay() {
    let lists = BoardLists(tasks: [
        BoardTask(id: "a.md", title: "a", status: .done, order: 1, done: "2026-11-24T09:00"),
        BoardTask(id: "c.md", title: "c", status: .done, order: 3, done: "2026-11-18T18:00"),
        BoardTask(id: "e.md", title: "e", status: .done, order: 5, done: "2026-11-10"),
    ], today: "2026-11-24", recentSince: "2026-11-18")
    #expect(lists.doneRecent.map(\.title) == ["a", "c"])
}
