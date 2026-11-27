// The focus session rules, with the clock in the test's hands.

import Foundation
import Testing

@testable import NowboardKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

// MARK: - Length

@Test func lengthsFromOneToOneHundredEightyAreValid() {
    for ok in [1, 15, 25, 50, 179, 180] { #expect(FocusSession.isValid(minutes: ok)) }
    for bad in [0, -5, 181, 1000, Int.max, Int.min] { #expect(!FocusSession.isValid(minutes: bad)) }
}

@Test func aLengthTypedByAPersonIsReadStrictly() {
    #expect(FocusSession.parse(minutes: "45") == 45)
    #expect(FocusSession.parse(minutes: "  90 ") == 90)
    for bad in ["", "abc", "0", "181", "-3", "12.5", "1e2", "٣٠", "25 min"] { #expect(FocusSession.parse(minutes: bad) == nil, "\(bad)") }
}

@Test func theDefaultIsTwentyFiveAndAnInvalidStartingLengthFallsBack() {
    #expect(FocusSession().minutes == 25)
    #expect(FocusSession(minutes: 0).minutes == 25)
    #expect(FocusSession(minutes: 999).minutes == 25)
    #expect(FocusSession(minutes: 50).minutes == 50)
    #expect(FocusSession.presets == [15, 25, 50])
}

@Test func theLengthAndTheTaskChangeOnlyWhileIdle() {
    var s = FocusSession()
    let r1 = s.setLength(minutes: 50)
    #expect(r1)
    let r2 = s.setTask("A.md")
    #expect(r2)
    let r3 = s.setLength(minutes: 0)
    #expect(!r3)  // invalid: unchanged
    let r4 = s.setLength(minutes: 181)
    #expect(!r4)
    #expect(s.minutes == 50)
    s.start(at: t0)
    let r5 = s.setLength(minutes: 15)
    #expect(!r5)
    let r6 = s.setTask("B.md")
    #expect(!r6)
    #expect(s.minutes == 50 && s.taskID == "A.md")
    s.pause(at: at(10))
    let r7 = s.setLength(minutes: 15)
    #expect(!r7)
    let r8 = s.setTask(nil)
    #expect(!r8)
    s.reset()
    let r9 = s.setLength(minutes: 15)
    #expect(r9)  // idle again
}

// MARK: - Running

@Test func startingCountsDownFromTheFullLength() {
    var s = FocusSession(minutes: 25)
    #expect(s.isIdle)
    #expect(s.remaining(at: t0) == 1500)
    #expect(s.fraction(at: t0) == 1)
    let r10 = s.start(at: t0)
    #expect(r10)
    #expect(s.isRunning && s.isActive)
    #expect(s.remaining(at: t0) == 1500)
    #expect(s.remaining(at: at(60)) == 1440)
    #expect(s.fraction(at: at(750)) == 0.5)
    let r11 = s.start(at: at(5))
    #expect(!r11)  // already running: no restart
    #expect(s.remaining(at: at(60)) == 1440)
}

@Test func theSessionFinishesExactlyAtZero() {
    var s = FocusSession(minutes: 1)
    s.start(at: t0)
    let r12 = s.updateFinished(at: at(59.999))
    #expect(!r12)
    #expect(s.isRunning)
    #expect(s.remaining(at: at(59.999)) > 0)
    let r13 = s.updateFinished(at: at(60))
    #expect(r13)  // exactly at the end counts
    #expect(s.isFinished && !s.isActive)
    #expect(s.remaining(at: at(60)) == 0)
    #expect(s.fraction(at: at(60)) == 0)
    let r14 = s.updateFinished(at: at(61))
    #expect(!r14)  // already finished: nothing more happens
}

@Test func remainingIsNeverNegativeEvenIfNobodyNoticedTheEnd() {
    var s = FocusSession(minutes: 1)
    s.start(at: t0)
    #expect(s.remaining(at: at(3600)) == 0)
    #expect(s.fraction(at: at(3600)) == 0)
}

@Test func aClockSetBackwardsNeverMakesTimeGrowBeyondTheLength() {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    #expect(s.remaining(at: at(-86_400)) == 1500)  // a day back: still just the full length
    #expect(s.fraction(at: at(-86_400)) == 1)
    let r15 = s.updateFinished(at: at(-86_400))
    #expect(!r15)
}

@Test func aClockJumpForwardFinishesTheSessionWhenItIsChecked() {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    // The Mac slept for two hours.
    let r16 = s.updateFinished(at: at(7200))
    #expect(r16)
    #expect(s.isFinished)
}

// MARK: - Pause and resume

@Test func pausingKeepsWhatIsLeftAndResumingContinuesFromIt() {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    let r17 = s.pause(at: at(600))
    #expect(r17)
    #expect(s.isPaused && s.isActive)
    #expect(s.remaining(at: at(600)) == 900)
    // Time passes while paused: nothing is used up.
    #expect(s.remaining(at: at(5000)) == 900)
    #expect(s.fraction(at: at(5000)) == 0.6)
    let r18 = s.resume(at: at(5000))
    #expect(r18)
    #expect(s.remaining(at: at(5000)) == 900)
    #expect(s.remaining(at: at(5300)) == 600)
    let r19 = s.updateFinished(at: at(5900))
    #expect(r19)
    #expect(s.isFinished)
}

@Test func pauseAndResumeOnlyWorkInTheRightStates() {
    var s = FocusSession()
    let r20 = s.pause(at: t0)
    #expect(!r20)  // idle
    let r21 = s.resume(at: t0)
    #expect(!r21)
    s.start(at: t0)
    let r22 = s.resume(at: at(1))
    #expect(!r22)  // running
    s.pause(at: at(10))
    let r23 = s.pause(at: at(11))
    #expect(!r23)  // already paused
    #expect(s.remaining(at: at(11)) == 1490)
}

@Test func pausingAfterTheEndFinishesInsteadOfPausing() {
    var s = FocusSession(minutes: 1)
    s.start(at: t0)
    let r24 = s.pause(at: at(61))
    #expect(!r24)
    #expect(s.isFinished)
}

@Test func manyPausesAddUpToTheFullLength() {
    var s = FocusSession(minutes: 10)
    s.start(at: t0)
    var now = 0.0
    for _ in 0..<5 {
        now += 60
        s.pause(at: at(now))
        now += 1000  // away
        s.resume(at: at(now))
    }
    #expect(s.remaining(at: at(now)) == 300)  // five minutes used
}

// MARK: - Reset and restart

@Test func resetGoesBackToIdleAndKeepsLengthAndTask() {
    var s = FocusSession(minutes: 50, taskID: "A.md")
    s.start(at: t0)
    s.pause(at: at(100))
    s.reset()
    #expect(s.isIdle)
    #expect(s.minutes == 50 && s.taskID == "A.md")
    #expect(s.remaining(at: at(500)) == 3000)
    s.reset()  // twice is fine
    #expect(s.isIdle)
}

@Test func anotherOneStartsAgainWithTheSameLengthAndTaskOnlyWhenFinished() {
    var s = FocusSession(minutes: 15, taskID: "A.md")
    let r25 = s.restart(at: t0)
    #expect(!r25)  // idle
    s.start(at: t0)
    let r26 = s.restart(at: at(10))
    #expect(!r26)  // running
    s.updateFinished(at: at(900))
    let r27 = s.restart(at: at(1000))
    #expect(r27)
    #expect(s.isRunning && s.minutes == 15 && s.taskID == "A.md")
    #expect(s.remaining(at: at(1000)) == 900)
}

// MARK: - Remembering

@Test func anIdleSessionIsNotRemembered() {
    #expect(FocusSession().encoded() == nil)
}

@Test func aRunningSessionComesBackRunningWithTheSameEnd() throws {
    var s = FocusSession(minutes: 25, taskID: "A.md")
    s.start(at: t0)
    let data = try #require(s.encoded())
    let back = try #require(FocusSession.restored(from: data, at: at(300)))
    #expect(back.isRunning)
    #expect(back.remaining(at: at(300)) == 1200)
    #expect(back.taskID == "A.md" && back.minutes == 25)
}

@Test func aRunningSessionWhoseEndPassedWhileClosedComesBackFinished() throws {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    let data = try #require(s.encoded())
    let exact = try #require(FocusSession.restored(from: data, at: at(1500)))  // exactly at the end
    let late = try #require(FocusSession.restored(from: data, at: at(100_000)))
    #expect(exact.isFinished && late.isFinished)
}

@Test func aPausedSessionComesBackPausedWhateverTheTime() throws {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    s.pause(at: at(600))
    let data = try #require(s.encoded())
    let back = try #require(FocusSession.restored(from: data, at: at(1_000_000)))
    #expect(back.isPaused)
    #expect(back.remaining(at: at(1_000_000)) == 900)
}

@Test func aFinishedSessionComesBackFinished() throws {
    var s = FocusSession(minutes: 1)
    s.start(at: t0)
    s.updateFinished(at: at(60))
    let data = try #require(s.encoded())
    let back = try #require(FocusSession.restored(from: data, at: at(61)))
    #expect(back.isFinished)
}

@Test func rubbishOrNonsenseIsNotRestored() throws {
    #expect(FocusSession.restored(from: Data("not json".utf8), at: t0) == nil)
    #expect(FocusSession.restored(from: Data(), at: t0) == nil)
    func json(_ phase: String, minutes: Int) -> Data {
        Data(#"{"phase": \#(phase), "minutes": \#(minutes)}"#.utf8)
    }
    // A length outside 1 to 180.
    #expect(FocusSession.restored(from: json(#"{"finished":{}}"#, minutes: 0), at: t0) == nil)
    #expect(FocusSession.restored(from: json(#"{"finished":{}}"#, minutes: 500), at: t0) == nil)
    // A pause with no time left, or more than the length.
    #expect(FocusSession.restored(from: json(#"{"paused":{"remaining":0}}"#, minutes: 25), at: t0) == nil)
    #expect(FocusSession.restored(from: json(#"{"paused":{"remaining":-5}}"#, minutes: 25), at: t0) == nil)
    #expect(FocusSession.restored(from: json(#"{"paused":{"remaining":99999}}"#, minutes: 25), at: t0) == nil)
    // An idle one is never a remembered session.
    #expect(FocusSession.restored(from: json(#"{"idle":{}}"#, minutes: 25), at: t0) == nil)
    // A sensible one is fine.
    #expect(FocusSession.restored(from: json(#"{"paused":{"remaining":600}}"#, minutes: 25), at: t0)?.isPaused == true)
}

// MARK: - Words

@Test func theTimeIsShownAsMinutesAndSeconds() {
    #expect(FocusSession.format(1471) == "24:31")
    #expect(FocusSession.format(1500) == "25:00")
    #expect(FocusSession.format(59.2) == "1:00")  // rounded up: never 0:00 while time is left
    #expect(FocusSession.format(0.1) == "0:01")
    #expect(FocusSession.format(0) == "0:00")
    #expect(FocusSession.format(-5) == "0:00")
    #expect(FocusSession.format(3600) == "1:00:00")
    #expect(FocusSession.format(10_800) == "3:00:00")
    #expect(FocusSession.format(3725) == "1:02:05")
}

// MARK: - The task picker

private func task(_ id: String, focus: Bool = false) -> BoardTask {
    BoardTask(id: id, title: id, status: .today, focus: focus)
}

@Test func theDefaultTaskIsTheFocusCardElseTheFirstTodayCardElseNone() {
    let a = task("A.md"), b = task("B.md", focus: true), c = task("C.md")
    #expect(FocusTaskChoice.automatic.resolve(today: [a, b, c]) == "B.md")
    #expect(FocusTaskChoice.automatic.resolve(today: [a, c]) == "A.md")
    #expect(FocusTaskChoice.automatic.resolve(today: []) == nil)
}

@Test func aChosenTaskWinsUntilItLeavesToday() {
    let a = task("A.md"), b = task("B.md", focus: true)
    #expect(FocusTaskChoice.task("A.md").resolve(today: [a, b]) == "A.md")
    #expect(FocusTaskChoice.task("A.md").resolve(today: [b]) == "B.md")  // finished: back to the default
    #expect(FocusTaskChoice.task("A.md").resolve(today: []) == nil)
}

@Test func noTaskMeansNoTaskEvenWhenThereAreCards() {
    #expect(FocusTaskChoice.none.resolve(today: [task("A.md")]) == nil)
}


@Test func aRunningEndFurtherAwayThanTheWholeLengthIsClamped() throws {
    var s = FocusSession(minutes: 25)
    s.start(at: t0)
    let data = try #require(s.encoded())
    // Restored at a time a day BEFORE it was saved (a clock that was far ahead): the end is clamped.
    let back = try #require(FocusSession.restored(from: data, at: at(-86_400)))
    #expect(back.isRunning)
    #expect(back.remaining(at: at(-86_400)) == 1500)
    if case .running(let end) = back.phase { #expect(end == at(-86_400 + 1500)) } else { Issue.record("expected running") }
}
