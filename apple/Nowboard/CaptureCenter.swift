// The state behind a future capture screen: the list of captures, the open
// question, whether something is running, and the actions. No screen uses it
// yet. All the work is done by `CapturePipeline` (NowboardKit); this class
// only keeps the results where SwiftUI can watch them.
//
// Swift note: `@Observable` makes SwiftUI redraw whatever reads these
// properties when they change. `@MainActor` means it all runs on the main
// thread, where screens live.

import Foundation
import NowboardKit
import Observation

@MainActor @Observable
final class CaptureCenter {
    /// Every raw capture in the Inbox, newest first.
    private(set) var entries: [InboxEntry] = []
    /// How many captures are being classified or waiting their turn.
    private(set) var pending = 0
    /// What went wrong the last time, as a sentence, or nil.
    private(set) var lastProblem: String?
    /// The text of a capture that could not even be saved (the disk refused). A screen should
    /// put it back in its text field instead of clearing it. Nil when the last capture was saved.
    private(set) var unsavedText: String?

    var isBusy: Bool { pending > 0 }

    /// The question to show now: the oldest capture that is waiting for an
    /// answer. Only one is shown at a time; the others wait behind it.
    var openQuestion: InboxEntry? {
        // `entries` is newest first, so the last waiting one is the oldest.
        entries.last { $0.outcome == .waitingForAnswer }
    }

    /// How many questions are waiting, including the open one.
    var waitingCount: Int { entries.filter { $0.outcome == .waitingForAnswer }.count }

    @ObservationIgnored private let pipeline: CapturePipeline
    @ObservationIgnored private let changes = Changes()

    init(
        config: VaultConfig, classifier: any Classifier, categoryIds: @escaping @Sendable () -> [String],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let changes = self.changes
        pipeline = CapturePipeline(
            config: config, classifier: classifier, categoryIds: categoryIds, now: now, onChange: { _ in changes.fire() })
        // The pipeline calls this from any thread; refresh on the main one.
        changes.handler = { [weak self] in Task { @MainActor in self?.refresh() } }
        refresh()
    }

    /// Reads the Inbox again.
    func refresh() {
        entries = pipeline.entries()
    }

    // MARK: Actions

    /// Saves and files a capture. The pipeline saves the text first, then classifies.
    /// If it can't be saved at all, `unsavedText` holds it.
    func capture(_ text: String) {
        unsavedText = nil
        pending += 1
        Task { [pipeline] in
            var problem: CaptureProblem?
            var failedText: String?
            do {
                problem = try await pipeline.capture(text).problem
            } catch {
                problem = .filing("Couldn't save the capture: \(error.localizedDescription)")
                failedText = text
            }
            pending -= 1
            lastProblem = problem?.errorDescription
            unsavedText = failedText
            refresh()
        }
    }

    /// Answers the open question.
    func answer(_ text: String) {
        guard let id = openQuestion?.id else { return }
        run { [pipeline] in
            do { return try await pipeline.answer(id, text: text).problem } catch { return .filing(error.localizedDescription) }
        }
    }

    /// Leaves the open question alone for good.
    func skip(_ id: String) {
        run { [pipeline] in
            do { _ = try await pipeline.skip(id); return nil } catch { return .filing(error.localizedDescription) }
        }
    }

    /// Takes back what was filed for a capture.
    func undo(_ id: String) {
        run { [pipeline] in
            do { _ = try await pipeline.undo(id); return nil } catch { return .filing(error.localizedDescription) }
        }
    }

    /// Classifies the captures that couldn't be classified before (offline…).
    func retry() {
        run { [pipeline] in await pipeline.retryUnclassified().compactMap(\.problem).first }
    }

    /// Runs one action in the background and keeps `pending` and `lastProblem` up to date.
    private func run(_ work: @escaping @Sendable () async -> CaptureProblem?) {
        pending += 1
        Task {
            let problem = await work()
            pending -= 1
            lastProblem = problem?.errorDescription
            refresh()
        }
    }
}

/// Lets the pipeline (built first) tell the center (built second) that something changed.
private final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable () -> Void)?
    var handler: (@Sendable () -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    func fire() { handler?() }
}
