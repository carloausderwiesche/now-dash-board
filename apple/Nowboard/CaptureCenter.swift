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
    /// A question whose answer is being classified right now isn't open any more: a new
    /// Return in the capture bar is a new capture, not a second answer to the same question.
    var openQuestion: InboxEntry? { InboxList.openQuestion(entries.filter { $0.id != answeringID }) }
    @ObservationIgnored private var answeringID: String?

    /// How many questions are waiting, including the open one (the Inbox tab's badge).
    var waitingCount: Int { InboxList.waitingCount(entries) }

    /// What just happened to the last capture or answer, for the strip above the
    /// capture bar. It fades by itself: `CaptureStrip.decide` stops showing it after a few seconds.
    private(set) var recent: RecentCapture?

    /// Where the vault and its folders are (the Inbox page opens notes from here).
    let config: VaultConfig
    @ObservationIgnored private let pipeline: CapturePipeline
    @ObservationIgnored private let changes = Changes()

    init(
        config: VaultConfig, classifier: any Classifier, categoryIds: @escaping @Sendable () -> [String],
        now: @escaping @Sendable () -> Date = { Date() }, guide: GuideMaintainer? = nil
    ) {
        let changes = self.changes
        self.config = config
        pipeline = CapturePipeline(
            config: config, classifier: classifier, categoryIds: categoryIds, now: now, onChange: { _ in changes.fire() }, guide: guide)
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
        lastProblem = nil
        recent = nil
        pending += 1
        Task { [pipeline] in
            var problem: CaptureProblem?
            var failedText: String?
            var report: CaptureReport?
            do {
                report = try await pipeline.capture(text)
                problem = report?.problem
            } catch {
                problem = .filing("Couldn't save the capture: \(error.localizedDescription)")
                failedText = text
            }
            pending -= 1
            // Only a failure sets these: a later capture that works must not wipe an earlier error unread.
            if let problem { lastProblem = problem.errorDescription }
            if let failedText { unsavedText = failedText }
            refresh()
            if let report { noteResult(report.entry) }
        }
    }

    /// Answers the open question.
    func answer(_ text: String) {
        guard let id = openQuestion?.id else { return }
        answeringID = id
        recent = nil
        lastProblem = nil
        pending += 1
        Task { [pipeline] in
            var problem: CaptureProblem?
            var report: CaptureReport?
            do {
                report = try await pipeline.answer(id, text: text)
                problem = report?.problem
            } catch {
                problem = .filing(error.localizedDescription)
            }
            pending -= 1
            if answeringID == id { answeringID = nil }
            if let problem {
                lastProblem = problem.errorDescription
                // The answer wasn't used, and unlike a capture it isn't saved anywhere: give it back.
                unsavedText = text
            }
            refresh()
            if let report { noteResult(report.entry) }
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
        recent = nil
        run { [pipeline] in
            do { _ = try await pipeline.undo(id); return nil } catch { return .filing(error.localizedDescription) }
        }
    }

    /// Classifies the captures that couldn't be classified before (offline…).
    func retry() {
        run { [pipeline] in await pipeline.retryUnclassified().compactMap(\.problem).first }
    }

    /// Hides the last error line (the person has read it).
    func dismissProblem() {
        lastProblem = nil
        unsavedText = nil
    }

    /// Hides the line about the last result (the person acted on it, or closed it).
    func dismissRecent() { recent = nil }

    /// Remembers a capture's outcome for the strip, if it has something to say.
    private func noteResult(_ entry: InboxEntry) {
        switch entry.outcome {
        case .taskSuggested?, .noteFiled?, .questionOpen?: recent = RecentCapture(entry: entry, at: Date())
        default: recent = nil
        }
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
