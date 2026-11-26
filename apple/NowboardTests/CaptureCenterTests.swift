// The state holder behind a future capture screen, with a fake classifier and
// a temporary vault: the list, the one open question, and the busy count.

import Foundation
import NowboardKit
import Testing

@testable import Nowboard

private struct FixedClassifier: Classifier {
    let answer: @Sendable (CaptureInput) -> CaptureResult
    func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult { answer(input) }
}

private func makeVault() throws -> URL {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-center-\(UUID().uuidString)")
    for dir in [".obsidian", "Notes/Tasks"] {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
    }
    return vault
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var minutes = 0
    func next() -> Date { lock.withLock { minutes += 1; return Date(timeIntervalSince1970: 1_800_000_000 + Double(minutes * 60)) } }
}

private func unclear(_ title: String) -> CaptureResult {
    CaptureResult(kind: .unclear, title: title, body: nil, area: "work", status: nil, folder: nil, confidence: 0.1, followUp: "Which \(title)?")
}

/// Waits until `condition` holds (the actions run in the background).
@MainActor private func eventually(_ condition: () -> Bool) async {
    for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor @Test func capturesShowUpAndTheOldestQuestionIsTheOpenOne() async throws {
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    // Each capture gets a clock a minute later, so the file names differ without waiting.
    let clock = Clock()
    let center = CaptureCenter(
        config: VaultConfig(vault: vault), classifier: FixedClassifier { unclear($0.text) }, categoryIds: { ["work"] },
        now: { clock.next() })
    #expect(center.entries.isEmpty)
    #expect(center.openQuestion == nil)

    center.capture("Mia")
    await eventually { center.entries.count == 1 && !center.isBusy }
    center.capture("Montag")
    await eventually { center.entries.count == 2 && !center.isBusy }

    #expect(center.waitingCount == 2)
    // Only one question at a time: the oldest.
    #expect(center.openQuestion?.text == "Mia")
    #expect(center.openQuestion?.followUp == "Which Mia?")
    #expect(!center.isBusy)

    // Skipping it brings the next one up.
    center.skip(try #require(center.openQuestion?.id))
    await eventually { center.waitingCount == 1 && !center.isBusy }
    #expect(center.openQuestion?.text == "Montag")
}

@MainActor @Test func aFailingClassifierShowsAProblemAndKeepsTheCapture() async throws {
    struct Down: Classifier {
        func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult { throw .cliNotFound }
    }
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: Down(), categoryIds: { ["work"] })
    center.capture("later")
    await eventually { center.entries.count == 1 && !center.isBusy }
    #expect(center.lastProblem?.contains("wasn't found") == true)
    #expect(center.entries.first?.outcome == nil)
    #expect(center.entries.first?.text == "later")
}

@MainActor @Test func aCaptureThatCantBeSavedComesBackAsUnsavedText() async throws {
    // The "vault" is a file, so the Inbox can't be made.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-notafolder-\(UUID().uuidString)")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let center = CaptureCenter(config: VaultConfig(vault: file), classifier: FixedClassifier { unclear($0.text) }, categoryIds: { ["work"] })
    center.capture("do not lose me")
    await eventually { !center.isBusy && center.unsavedText != nil }
    #expect(center.unsavedText == "do not lose me")
    #expect(center.lastProblem?.contains("Couldn't save the capture") == true)
}

@MainActor @Test func theLastResultIsKeptForTheStripAndClearedOnUndo() async throws {
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let task = FixedClassifier { CaptureResult(kind: .task, title: $0.text, area: "work", confidence: 0.9) }
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: task, categoryIds: { ["work"] })
    center.capture("Buy milk")
    await eventually { center.recent != nil && !center.isBusy }
    #expect(center.recent?.entry.outcome == .taskSuggested)
    // The strip decision uses it (pure function, tested in NowboardKit).
    let strip = CaptureStrip.decide(CaptureStripInput(recent: center.recent, now: center.recent?.at ?? Date()))
    if case .result(_, _, let canUndo)? = strip { #expect(canUndo) } else { Issue.record("expected a result strip") }

    center.undo(try #require(center.recent?.entry.id))
    await eventually { center.recent == nil && !center.isBusy }
    #expect(center.entries.first?.outcome == .skipped)
}

@MainActor @Test func aQuestionOpensAndAnsweringItClosesIt() async throws {
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let classifier = FixedClassifier { input in
        input.answer == nil ? unclear(input.text) : CaptureResult(kind: .task, title: "Call Mia", area: "work", confidence: 0.9)
    }
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: classifier, categoryIds: { ["work"] })
    center.capture("Mia")
    await eventually { center.openQuestion != nil && !center.isBusy }
    #expect(center.waitingCount == 1)
    center.answer("It's a task.")
    await eventually { center.openQuestion == nil && !center.isBusy }
    #expect(center.entries.first?.outcome == .taskSuggested)
    #expect(center.recent?.entry.outcome == .taskSuggested)
    center.dismissRecent()
    #expect(center.recent == nil)
}

@MainActor @Test func aSecondReturnWhileAnAnswerIsBeingSortedIsANewCaptureNotAnotherAnswer() async throws {
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let classifier = SlowClassifier()
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: classifier, categoryIds: { ["work"] })
    center.capture("Mia")
    await eventually { center.openQuestion != nil && !center.isBusy }
    center.answer("task")
    // While that answer is being classified the question is no longer open.
    #expect(center.openQuestion == nil)
    await eventually { !center.isBusy }
    #expect(center.lastProblem == nil)
}

@MainActor @Test func anAnswerThatFailsComesBackAsUnsavedText() async throws {
    struct FailsOnAnswer: Classifier {
        func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult {
            if input.answer != nil { throw .timedOut }
            return unclear(input.text)
        }
    }
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: FailsOnAnswer(), categoryIds: { ["work"] })
    center.capture("Mia")
    await eventually { center.openQuestion != nil && !center.isBusy }
    center.answer("it is a task")
    await eventually { !center.isBusy && center.unsavedText != nil }
    #expect(center.unsavedText == "it is a task")
    #expect(center.lastProblem?.contains("too long") == true)
    // The question is open again.
    #expect(center.openQuestion?.text == "Mia")
}

@MainActor @Test func aLaterSuccessDoesNotWipeAnEarlierErrorUnread() async throws {
    let vault = try makeVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let flaky = FlakyClassifier()
    let center = CaptureCenter(config: VaultConfig(vault: vault), classifier: flaky, categoryIds: { ["work"] })
    center.capture("first")  // fails (slow)
    center.capture("second")  // works
    await eventually { !center.isBusy }
    #expect(center.lastProblem != nil)
}

private struct SlowClassifier: Classifier {
    func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult {
        try? await Task.sleep(for: .milliseconds(200))
        return input.answer == nil ? unclear(input.text) : CaptureResult(kind: .task, title: "T", area: "work", confidence: 0.9)
    }
}

private struct FlakyClassifier: Classifier {
    func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult {
        if input.text == "first" { throw .timedOut }
        return CaptureResult(kind: .task, title: input.text, area: "work", confidence: 0.9)
    }
}
