// What the capture bar's strip and the Inbox page say.

import Foundation
import Testing

@testable import NowboardKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(
    _ id: String = "2026-11-26 13-05-22.md", text: String = "typed", outcome: InboxOutcome? = nil, followUp: String? = nil,
    taskFile: String? = nil, notePath: String? = nil, dailyLine: String? = nil, notice: String? = nil
) -> InboxEntry {
    InboxEntry(
        id: id, text: text, captured: "2026-11-26T13:05", outcome: outcome, followUp: followUp, taskFile: taskFile, notePath: notePath,
        dailyLine: dailyLine, notice: notice)
}

private func recent(_ e: InboxEntry, secondsAgo: Double = 1, category: String? = nil) -> RecentCapture {
    RecentCapture(entry: e, at: t0.addingTimeInterval(-secondsAgo), categoryName: category)
}

// MARK: - The strip

@Test func nothingToSayMeansNoStrip() {
    #expect(CaptureStrip.decide(CaptureStripInput(now: t0)) == nil)
}

@Test func whileSortingTheStripSaysSorting() {
    #expect(CaptureStrip.decide(CaptureStripInput(pending: 1, now: t0)) == .sorting)
    // Even with a question open or a result waiting: the new capture comes first.
    let q = entry(outcome: .waitingForAnswer)
    #expect(CaptureStrip.decide(CaptureStripInput(pending: 2, openQuestion: q, waitingCount: 1, now: t0)) == .sorting)
}

@Test func anErrorShowsItsMessageAndWhetherTheTextIsSafe() {
    let saved = CaptureStrip.decide(CaptureStripInput(problem: "Claude took too long to answer.", now: t0))
    #expect(saved == .problem(message: "Claude took too long to answer.", textSaved: true))
    let lost = CaptureStrip.decide(CaptureStripInput(problem: "Couldn't save the capture: disk full", textUnsaved: true, now: t0))
    #expect(lost == .problem(message: "Couldn't save the capture: disk full", textSaved: false))
}

@Test func anErrorOutranksAQuestionAndAResult() {
    let q = entry(outcome: .waitingForAnswer)
    let input = CaptureStripInput(problem: "boom", openQuestion: q, waitingCount: 1, recent: recent(entry(outcome: .noteFiled)), now: t0)
    #expect(CaptureStrip.decide(input) == .problem(message: "boom", textSaved: true))
}

@Test func aWaitingCaptureShowsItsQuestionAndHowManyWaitBehindIt() {
    let q = entry("a.md", text: "Mia", outcome: .waitingForAnswer, followUp: "What about Mia?")
    let strip = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 3, now: t0))
    #expect(strip == .question(entryID: "a.md", typed: "Mia", question: "What about Mia?", others: 2))
}

@Test func aQuestionWithoutTextGetsTheDefaultOne() {
    let q = entry(outcome: .waitingForAnswer)
    guard case .question(_, _, let question, let others)? = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 1, now: t0))
    else {
        Issue.record("expected a question")
        return
    }
    #expect(question == CaptureResult.defaultQuestion)
    #expect(others == 0)
}

@Test func aQuestionOutranksAFreshResult() {
    let q = entry("q.md", outcome: .waitingForAnswer, followUp: "Which?")
    let done = recent(entry("d.md", outcome: .taskSuggested, taskFile: "T.md"))
    let strip = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 1, recent: done, now: t0))
    if case .question? = strip {} else { Issue.record("got \(String(describing: strip))") }
}

@Test func aSuggestedTaskShowsItsCategoryAndUndo() {
    let e = entry("t.md", outcome: .taskSuggested, taskFile: "Call the dentist.md")
    let strip = CaptureStrip.decide(CaptureStripInput(recent: recent(e, category: "Work"), now: t0))
    #expect(strip == .result(entryID: "t.md", message: "Task suggested in Work", canUndo: true))
    // Without a category name it still says something true.
    let plain = CaptureStrip.decide(CaptureStripInput(recent: recent(e), now: t0))
    #expect(plain == .result(entryID: "t.md", message: "Task suggested", canUndo: true))
}

@Test func aFiledNoteSaysWhereAndThatTheDailyNoteGotALine() {
    let e = entry("n.md", outcome: .noteFiled, notePath: "Wiki/Ideas/Title.md", dailyLine: "- 13:05 [[Wiki/Ideas/Title]]")
    #expect(
        CaptureStrip.decide(CaptureStripInput(recent: recent(e), now: t0))
            == .result(entryID: "n.md", message: "Note filed under Wiki/Ideas, added to today's daily note", canUndo: true))
    // No daily note line: it doesn't claim one. A notice (a fallback folder, say) is added.
    let fallback = entry(
        "n.md", outcome: .noteFiled, notePath: "Notes/Inbox/Title.md", notice: "The suggested folder “x” can't be used, so the note is in Notes/Inbox.")
    guard case .result(_, let message, _)? = CaptureStrip.decide(CaptureStripInput(recent: recent(fallback), now: t0)) else {
        Issue.record("expected a result")
        return
    }
    #expect(message.hasPrefix("Note filed under Notes/Inbox. The suggested folder"))
    #expect(!message.contains("daily note"))
}

@Test func aNoteInTheVaultRootIsDescribedHonestly() {
    let e = entry(outcome: .noteFiled, notePath: "Title.md")
    #expect(InboxText.outcome(e, categoryName: nil) == "Note filed in the top folder of the vault")
}

@Test func aResultFadesAfterAFewSeconds() {
    let e = entry(outcome: .taskSuggested, taskFile: "T.md")
    #expect(CaptureStrip.decide(CaptureStripInput(recent: recent(e, secondsAgo: 7.9), now: t0)) != nil)
    #expect(CaptureStrip.decide(CaptureStripInput(recent: recent(e, secondsAgo: 8), now: t0)) == nil)
    #expect(CaptureStrip.decide(CaptureStripInput(recent: recent(e, secondsAgo: 60), now: t0)) == nil)
}

@Test func aQuestionResultIsHonestThatAnsweringComesLater() {
    let e = entry("q.md", outcome: .questionOpen)
    guard case .questionLater(let id, let message)? = CaptureStrip.decide(CaptureStripInput(recent: recent(e), now: t0)) else {
        Issue.record("expected the question line")
        return
    }
    #expect(id == "q.md")
    #expect(message.contains("later version"))
}

@Test func outcomesThatNeedNoLineGiveNoStrip() {
    for outcome in [InboxOutcome.skipped, .answered, nil] as [InboxOutcome?] {
        #expect(CaptureStrip.decide(CaptureStripInput(recent: recent(entry(outcome: outcome)), now: t0)) == nil)
    }
}

// MARK: - The Inbox page

@Test func everyOutcomeHasWords() {
    for outcome in InboxOutcome.allCases {
        #expect(InboxText.outcome(entry(outcome: outcome), categoryName: nil).isEmpty == false)
    }
    #expect(InboxText.outcome(entry(), categoryName: nil) == "Not sorted yet")
    #expect(InboxText.outcome(entry(outcome: .skipped), categoryName: nil) == "Skipped")
}

@Test func undoIsOnlyOfferedWhereSomethingWasFiled() {
    #expect(InboxText.canUndo(entry(outcome: .taskSuggested, taskFile: "T.md")))
    #expect(InboxText.canUndo(entry(outcome: .noteFiled, notePath: "A.md")))
    #expect(!InboxText.canUndo(entry(outcome: .waitingForAnswer)))
    #expect(!InboxText.canUndo(entry(outcome: .skipped)))
    #expect(!InboxText.canUndo(entry()))
}

@Test func theInboxListPutsWaitingFirstThenNewestFirst() {
    let a = entry("2026-11-26 09-00-00.md", text: "a", outcome: .noteFiled)
    let b = entry("2026-11-26 10-00-00.md", text: "b", outcome: .waitingForAnswer)
    let c = entry("2026-11-26 11-00-00.md", text: "c", outcome: .taskSuggested)
    let d = entry("2026-11-26 12-00-00.md", text: "d", outcome: .waitingForAnswer)
    let e = entry("2026-11-26 13-00-00.md", text: "e")
    // Waiting ones: the one asked first on top. The rest: newest first.
    #expect(InboxList.ordered([a, b, c, d, e]).map(\.text) == ["b", "d", "e", "c", "a"])
    #expect(InboxList.ordered([]).isEmpty)
}

@Test func theBadgeCountsOnlyCapturesWaitingForAnAnswer() {
    let list = [entry("a.md", outcome: .waitingForAnswer), entry("b.md", outcome: .questionOpen), entry("c.md", outcome: .waitingForAnswer), entry("d.md")]
    #expect(InboxList.waitingCount(list) == 2)
    #expect(InboxList.waitingCount([]) == 0)
}

@Test func theOpenQuestionIsTheOldestWaitingOne() {
    let newer = entry("2026-11-26 13-05-22 (2).md", text: "newer", outcome: .waitingForAnswer)
    let older = entry("2026-11-26 13-05-22.md", text: "older", outcome: .waitingForAnswer)
    let other = entry("2026-11-26 09-00-00.md", text: "done", outcome: .noteFiled)
    #expect(InboxList.openQuestion([newer, other, older])?.text == "older")
    #expect(InboxList.openQuestion([other]) == nil)
}

// MARK: - Focus sessions

@Test func aRunningFocusSessionHidesTheQuestionButNotTheRest() {
    let q = entry("q.md", text: "Mia", outcome: .waitingForAnswer, followUp: "Which?")
    let waiting = CaptureStripInput(openQuestion: q, waitingCount: 2, now: t0, sessionRunning: true)
    #expect(CaptureStrip.decide(waiting) == nil)  // nothing interrupts
    // Without a session the same input asks.
    if case .question? = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 2, now: t0)) {} else { Issue.record("expected the question") }
    // Sorting and errors still show: they are about what you just did.
    #expect(CaptureStrip.decide(CaptureStripInput(pending: 1, openQuestion: q, now: t0, sessionRunning: true)) == .sorting)
    #expect(CaptureStrip.decide(CaptureStripInput(problem: "boom", openQuestion: q, now: t0, sessionRunning: true)) == .problem(message: "boom", textSaved: true))
}

@Test func aResultStillShowsDuringASessionAndTheQuestionComesBackAfterwards() {
    let q = entry("q.md", outcome: .waitingForAnswer, followUp: "Which?")
    let done = recent(entry("d.md", outcome: .taskSuggested, taskFile: "T.md"))
    // During the session: the result of a new capture shows, the question doesn't.
    let during = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 1, recent: done, now: t0, sessionRunning: true))
    if case .result? = during {} else { Issue.record("got \(String(describing: during))") }
    // After it: the question is back, ahead of the result, as before.
    let after = CaptureStrip.decide(CaptureStripInput(openQuestion: q, waitingCount: 1, recent: done, now: t0, sessionRunning: false))
    if case .question? = after {} else { Issue.record("got \(String(describing: after))") }
}
