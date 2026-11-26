// The focus session as the app uses it: the rules live in NowboardKit
// (`FocusSession`); this class adds what only the app can do: the clock, the
// task board, the settings, and waking up after sleep.
//
// Swift note: `@Observable` makes SwiftUI redraw what reads it when it
// changes. `@MainActor` keeps it on the main thread, where screens live.

#if os(macOS)
    import AppKit
    import NowboardKit
    import Observation

    @MainActor @Observable
    final class FocusSessionModel {
        private(set) var session = FocusSession()
        /// What the task picker shows while idle.
        var choice = FocusTaskChoice.automatic

        @ObservationIgnored private weak var store: BoardStore?
        /// Waits for the end of a running session, then notices that it is over.
        @ObservationIgnored private var finishTimer: Task<Void, Never>?
        @ObservationIgnored private var observers: [NSObjectProtocol] = []

        /// Connects to the board, restores a remembered session and starts watching for the end.
        func attach(to store: BoardStore) {
            guard self.store == nil else { return }
            self.store = store
            if let data = store.settings.focusSessionData {
                if let restored = FocusSession.restored(from: data, at: Date()) {
                    session = restored
                    if let id = restored.taskID { choice = .task(id) }
                } else {
                    // Unreadable or nonsense: forget it.
                    store.settings.focusSessionData = nil
                }
            }
            persist()
            scheduleFinish()
            // After the Mac wakes up, or the app comes forward, the end may have passed.
            let center = NotificationCenter.default
            let wake = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
            let active = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            observers = [wake, active]
        }

        // MARK: - What the picker offers

        /// The Today cards, in order: the tasks a session can be for.
        var todayTasks: [BoardTask] { store?.lists.today ?? [] }

        /// The task a session started now would be for.
        var pickedTaskID: String? { choice.resolve(today: todayTasks) }

        /// The title of the task the session is linked to, if it still exists.
        func title(of id: String?) -> String? { id.flatMap { store?.task($0)?.title } }

        // MARK: - Actions

        /// Starts from idle. With a task, that task becomes the one focus card
        /// (the board's own focus toggle; if it already is the focus card, nothing changes).
        func start() {
            guard session.isIdle, let store else { return }
            let id = pickedTaskID
            session.setTask(id)
            guard session.start(at: Date()) else { return }
            if let id, let task = store.task(id), !task.focus { store.toggleFocus(id) }
            changed()
        }

        func pause() {
            session.pause(at: Date())
            changed()
        }

        func resume() {
            session.resume(at: Date())
            changed()
        }

        /// Back to idle. The focus card stays as it is.
        func reset() {
            session.reset()
            changed()
        }

        func setLength(_ minutes: Int) {
            session.setLength(minutes: minutes)
            changed()
        }

        /// The linked task still exists and isn't done yet (it may have been finished on the board meanwhile).
        var canMarkDone: Bool {
            guard let id = session.taskID, let task = store?.task(id) else { return false }
            return task.status != .done
        }

        /// "Mark task done": finishes the linked task through the board's own action, then back to idle.
        func markTaskDone() {
            // Only a task that isn't done yet: finishing again would stamp a new time on it.
            if canMarkDone, let id = session.taskID { store?.finish(id) }
            session.reset()
            choice = .automatic
            changed()
        }

        /// "Another one": the same length and task again.
        func anotherOne() {
            session.restart(at: Date())
            changed()
        }

        // MARK: - Time

        /// Notices that the end has come (also called by the timer and after waking up).
        func check() {
            if session.updateFinished(at: Date()) {
                changed()
            } else if session.isRunning {
                // Woken too early (the clock was set back): wait again for the real end.
                scheduleFinish()
            }
        }

        /// A running session needs a wake-up at its end; nothing ticks otherwise
        /// (the ring's once-a-second redraw is the box's own, and only while running).
        private func scheduleFinish() {
            finishTimer?.cancel()
            guard case .running(let end) = session.phase else { return }
            finishTimer = Task { [weak self] in
                // `ContinuousClock` keeps counting while the Mac sleeps, so a lid closed
                // for ten minutes doesn't push the end ten minutes later.
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)), clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }

        private func changed() {
            persist()
            scheduleFinish()
        }

        /// Remembers a running, paused or finished session (an idle one is nothing to remember).
        private func persist() {
            // Only when it differs: writing the settings rewrites them on disk.
            let data = session.encoded()
            if store?.settings.focusSessionData != data { store?.settings.focusSessionData = data }
        }

        #if DEBUG
            /// `-focusDemo running|paused|finished`: a session in that state, for snapshots.
            func applyDebugArguments() {
                guard let state = DebugSnapshot.argument("focusDemo") else { return }
                // After the demo board has loaded its cards.
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    var demo = FocusSession(minutes: 25, taskID: todayTasks.first(where: \.focus)?.id ?? todayTasks.first?.id)
                    let now = Date()
                    switch state {
                    case "running":
                        demo.start(at: now.addingTimeInterval(-(25 * 60 - (18 * 60 + 44))))  // about 18:42 left once it is drawn
                    case "paused":
                        demo.start(at: now)
                        demo.pause(at: now.addingTimeInterval(7 * 60 + 5))
                    case "finished":
                        demo.start(at: now.addingTimeInterval(-26 * 60))
                        demo.updateFinished(at: now)
                    default: return
                    }
                    session = demo
                    if let id = demo.taskID { choice = .task(id) }
                    scheduleFinish()
                }
            }
        #endif
    }
#endif
