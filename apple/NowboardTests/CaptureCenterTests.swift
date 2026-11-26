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
