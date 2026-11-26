// The focus session as the app runs it: starting makes the task the one focus
// card, the session is remembered in the settings, and "Mark task done" uses
// the board's own action. Against a temporary Tasks folder, never a real one.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Testing

    @testable import Nowboard

    @MainActor
    private func makeStore(_ files: [String: String]) async throws -> (BoardStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        let store = BoardStore(testFolder: dir)
        await store.reload()
        return (store, dir)
    }

    private let today = "---\nstatus: today\narea: work\norder: 1\n---\n"

    @MainActor @Test func startingWithATaskMakesItTheOnlyFocusCard() async throws {
        let (store, dir) = try await makeStore(["A.md": today, "B.md": today.replacingOccurrences(of: "order: 1", with: "order: 2") .replacingOccurrences(of: "area: work", with: "area: work\nfocus: true")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = FocusSessionModel()
        model.attach(to: store)
        // Default task: the current focus card (B).
        #expect(model.pickedTaskID == "B.md")
        model.choice = .task("A.md")
        model.start()
        #expect(model.session.isRunning)
        #expect(model.session.taskID == "A.md")
        #expect(store.task("A.md")?.focus == true)
        #expect(store.task("B.md")?.focus == false)  // only one focus card
        await store.waitForWrites()
    }

    @MainActor @Test func startingWithTheCardAlreadyInFocusLeavesItInFocus() async throws {
        let (store, dir) = try await makeStore(["A.md": today.replacingOccurrences(of: "area: work", with: "area: work\nfocus: true")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = FocusSessionModel()
        model.attach(to: store)
        model.start()
        #expect(store.task("A.md")?.focus == true)  // not toggled off
    }

    @MainActor @Test func noTaskMeansNoFocusChange() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = FocusSessionModel()
        model.attach(to: store)
        model.choice = .none
        model.start()
        #expect(model.session.isRunning && model.session.taskID == nil)
        #expect(store.task("A.md")?.focus == false)
    }

    @MainActor @Test func resetAndFinishingDoNotChangeTheFocusCard() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = FocusSessionModel()
        model.attach(to: store)
        model.start()
        #expect(store.task("A.md")?.focus == true)
        model.reset()
        #expect(model.session.isIdle)
        #expect(store.task("A.md")?.focus == true)
    }

    @MainActor @Test func theSessionIsRememberedInTheSettingsAndRestoredByANewModel() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = FocusSessionModel()
        first.attach(to: store)
        first.setLength(50)
        first.start()
        #expect(store.settings.focusSessionData != nil)
        first.pause()
        // "Quit and reopen": a new model on the same settings.
        let second = FocusSessionModel()
        second.attach(to: store)
        #expect(second.session.isPaused)
        #expect(second.session.minutes == 50)
        #expect(second.session.taskID == "A.md")
        // Reset forgets it.
        second.reset()
        #expect(store.settings.focusSessionData == nil)
    }

    @MainActor @Test func aSessionThatRanOutWhileTheAppWasClosedComesBackFinished() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        var old = FocusSession(minutes: 25, taskID: "A.md")
        old.start(at: Date().addingTimeInterval(-3600))
        store.settings.focusSessionData = old.encoded()
        let model = FocusSessionModel()
        model.attach(to: store)
        #expect(model.session.isFinished)
    }

    @MainActor @Test func unreadableRememberedDataIsForgotten() async throws {
        let (store, dir) = try await makeStore([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        store.settings.focusSessionData = Data("garbage".utf8)
        let model = FocusSessionModel()
        model.attach(to: store)
        #expect(model.session.isIdle)
        #expect(store.settings.focusSessionData == nil)
    }

    @MainActor @Test func markTaskDoneFinishesTheLinkedTaskAndGoesIdle() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        var finished = FocusSession(minutes: 1, taskID: "A.md")
        finished.start(at: Date().addingTimeInterval(-120))
        store.settings.focusSessionData = finished.encoded()
        let model = FocusSessionModel()
        model.attach(to: store)
        #expect(model.session.isFinished)
        model.markTaskDone()
        #expect(model.session.isIdle)
        await store.waitForWrites()
        try await Task.sleep(for: .seconds(1.5))  // the card's flight into Done
        await store.waitForWrites()
        #expect(store.task("A.md")?.status == .done)
    }

    @MainActor @Test func markTaskDoneLeavesATaskThatIsAlreadyDoneAlone() async throws {
        let done = "---\nstatus: done\narea: work\ndone: 2026-11-20T10:00\n---\n"
        let (store, dir) = try await makeStore(["A.md": done])
        defer { try? FileManager.default.removeItem(at: dir) }
        var finished = FocusSession(minutes: 1, taskID: "A.md")
        finished.start(at: Date().addingTimeInterval(-120))
        store.settings.focusSessionData = finished.encoded()
        let model = FocusSessionModel()
        model.attach(to: store)
        #expect(!model.canMarkDone)
        model.markTaskDone()
        await store.waitForWrites()
        #expect(store.task("A.md")?.done == "2026-11-20T10:00")  // not re-stamped
    }

    @MainActor @Test func anotherOneRestartsWithTheSameLengthAndTask() async throws {
        let (store, dir) = try await makeStore(["A.md": today])
        defer { try? FileManager.default.removeItem(at: dir) }
        var finished = FocusSession(minutes: 15, taskID: "A.md")
        finished.start(at: Date().addingTimeInterval(-1000))
        store.settings.focusSessionData = finished.encoded()
        let model = FocusSessionModel()
        model.attach(to: store)
        #expect(model.session.isFinished)
        model.anotherOne()
        #expect(model.session.isRunning)
        #expect(model.session.minutes == 15 && model.session.taskID == "A.md")
    }

    @MainActor @Test func theLengthCannotChangeWhileRunning() async throws {
        let (store, dir) = try await makeStore([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = FocusSessionModel()
        model.attach(to: store)
        model.start()
        model.setLength(50)
        #expect(model.session.minutes == 25)
    }

    @Test func oldSettingsWithoutASessionStillLoad() throws {
        let old = #"{"theme":"braun","density":"roomy","categories":[{"id":"work","name":"Work","color":"blue"}]}"#
        #expect(try JSONDecoder().decode(DeviceSettings.self, from: Data(old.utf8)).focusSessionData == nil)
        var settings = DeviceSettings()
        settings.focusSessionData = Data("x".utf8)
        let again = try JSONDecoder().decode(DeviceSettings.self, from: JSONEncoder().encode(settings))
        #expect(again.focusSessionData == Data("x".utf8))
    }
#endif
