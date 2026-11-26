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
    let center = CaptureCenter(
        config: VaultConfig(vault: vault), classifier: FixedClassifier { unclear($0.text) }, categoryIds: { ["work"] })
    #expect(center.entries.isEmpty)
    #expect(center.openQuestion == nil)

    center.capture("Mia")
    await eventually { center.entries.count == 1 && !center.isBusy }
    try await Task.sleep(for: .milliseconds(1100))  // the next capture gets a later file name
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
