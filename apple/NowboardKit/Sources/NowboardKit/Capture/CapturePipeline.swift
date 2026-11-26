// From a typed capture to changes in the vault (docs/capture-format.md,
// sections 9 to 11). Strictly in this order, for every capture:
//
//   a. the typed text is saved as a raw file in the Inbox (nothing else may
//      happen before that, so nothing typed is ever lost);
//   b. the classifier is asked;
//   c. the result is applied: a suggested task, a filed note, a question;
//   d. what happened is written into the raw file's frontmatter (never its text).
//
// No screen is involved, and no process: the classifier is passed in, so all
// of this is tested with a fake one against a temporary vault.

import CryptoKit
import Foundation

// MARK: - Results and errors

/// What went wrong with one capture. The raw text is safe in every case.
public enum CaptureProblem: Error, Equatable, LocalizedError {
    /// The classifier failed (offline, tool error, timeout…). The capture has
    /// no outcome, which means "not classified yet": retry it later.
    case classifier(ClassifierError)
    /// The classifier answered but filing the result failed (disk, permissions).
    case filing(String)

    public var errorDescription: String? {
        switch self {
        case .classifier(let error): error.errorDescription
        case .filing(let why): "Couldn't file the result: \(why)"
        }
    }
}

/// What `capture`, `answer` and `retry` give back: the entry as it is now,
/// and what went wrong, if anything.
public struct CaptureReport: Sendable, Equatable {
    public var entry: InboxEntry
    public var problem: CaptureProblem?
}

/// What can go wrong with the actions on an existing entry.
public enum PipelineError: Error, Equatable, LocalizedError {
    case notFound(String)
    /// An answer was given for an entry that isn't waiting for one.
    case notWaiting(String)
    case emptyAnswer
    /// Undo refused: the file the app made has been changed since, so it isn't ours to delete.
    case changedSince(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "No capture named \(id)."
        case .notWaiting: "That capture isn't waiting for an answer."
        case .emptyAnswer: "There is no answer to send."
        case .changedSince(let what): "Not undone: \(what) was changed after it was made, so it was left alone."
        case .io(let why): why
        }
    }
}

// MARK: - One at a time

/// A first-in first-out lock for async code: only one piece of work holds it
/// at a time, the others wait in the order they asked.
///
/// Swift note: an `actor` looks after its own data, one caller at a time. But
/// an actor method that waits (`await`) lets another caller in meanwhile, so
/// an actor alone would NOT stop two classifications running together. This
/// small queue does.
actor SerialQueue {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
    }

    func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()  // the next in line keeps the lock
        }
    }
}

// MARK: - The pipeline

public final class CapturePipeline: Sendable {
    public let config: VaultConfig
    private let classifier: any Classifier
    private let categoryIds: @Sendable () -> [String]
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private let onChange: (@Sendable (InboxEntry) -> Void)?
    private let queue = SerialQueue()

    /// - `categoryIds`: the board's categories right now (asked at each use).
    /// - `onChange`: told about an entry whenever it changes (saved, filed…), so a screen can refresh.
    public init(
        config: VaultConfig, classifier: any Classifier, categoryIds: @escaping @Sendable () -> [String],
        now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current,
        onChange: (@Sendable (InboxEntry) -> Void)? = nil
    ) {
        self.config = config
        self.classifier = classifier
        self.categoryIds = categoryIds
        self.now = now
        self.timeZone = timeZone
        self.onChange = onChange
    }

    // MARK: Actions

    /// Takes a capture: saves the typed text first, then classifies and files it.
    /// Throws only if the text can't be saved at all. A failing classifier
    /// is reported in `problem`; the capture stays in the Inbox.
    @discardableResult
    public func capture(_ text: String) async throws(CaptureError) -> CaptureReport {
        // (a) First, and straight away, even if another capture is being classified.
        let name = try config.inbox.writeRaw(text, at: now(), timeZone: timeZone)
        notify(name)
        // (b) to (d), one capture at a time, in the order they came.
        let problem = await serially { await self.process(name, answer: nil) }
        return CaptureReport(entry: entry(name), problem: problem)
    }

    /// Answers the question of an entry that is `waiting-for-answer`: the
    /// original text and the answer are classified again, in a new call (the
    /// pipeline remembers nothing between calls).
    @discardableResult
    public func answer(_ id: String, text: String) async throws(PipelineError) -> CaptureReport {
        guard text.trimmedOrNil != nil else { throw .emptyAnswer }
        // Checked again inside the queue: two answers at once must not both pass,
        // or the second one would be dropped without a word.
        let problem = try await serially { () async throws(PipelineError) -> CaptureProblem? in
            guard try self.read(id).outcome == .waitingForAnswer else { throw .notWaiting(id) }
            return await self.process(id, answer: text)
        }
        return CaptureReport(entry: entry(id), problem: problem)
    }

    /// Classifies every capture that has no outcome yet (the classifier was
    /// down when it was typed), oldest first, one at a time.
    @discardableResult
    public func retryUnclassified() async -> [CaptureReport] {
        await serially {
            var reports: [CaptureReport] = []
            // Re-listed each time: other work may have handled some meanwhile.
            for entry in self.entries().filter({ $0.outcome == nil }).sorted(by: { $0.sortKey < $1.sortKey }) {
                let problem = await self.process(entry.id, answer: nil)
                reports.append(CaptureReport(entry: self.entry(entry.id), problem: problem))
            }
            return reports
        }
    }

    /// Leaves a capture alone for good: outcome `skipped`. For one the app
    /// filed something for, use `undo` instead.
    @discardableResult
    public func skip(_ id: String) async throws(PipelineError) -> InboxEntry {
        try await serially { () async throws(PipelineError) -> InboxEntry in
            let current = try self.read(id)
            guard !current.hasFiledResult else { throw .io("Use Undo for a capture that was filed.") }
            return try self.record(id, InboxUpdate(.skipped))
        }
    }

    /// Takes back what the app made for a capture (spec 11): the suggested
    /// task file, or the filed note and its daily-note line, then marks the
    /// capture `skipped`. It only deletes files the app made itself, and only
    /// if they are still as the app made them.
    @discardableResult
    public func undo(_ id: String) async throws(PipelineError) -> InboxEntry {
        try await serially { () async throws(PipelineError) -> InboxEntry in try self.undoNow(id) }
    }

    /// All raw captures in the Inbox, newest first.
    public func entries() -> [InboxEntry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: config.inbox.url.path)) ?? []
        return names.filter { !TaskFormat.isIgnored($0) }
            .compactMap { name -> InboxEntry? in
                guard let text = try? String(contentsOf: config.inbox.url.appendingPathComponent(name), encoding: .utf8) else { return nil }
                let entry = InboxEntry.parse(id: name, text: text)
                // Only files the app wrote as captures: a note someone dropped in the Inbox isn't one.
                return entry.captured == nil ? nil : entry
            }
            .sorted { $0.sortKey > $1.sortKey }
    }

    // MARK: The work

    /// Runs `work` when it's our turn.
    private func serially<T: Sendable>(_ work: () async -> T) async -> T {
        await queue.acquire()
        let result = await work()
        await queue.release()
        return result
    }

    private func serially<T: Sendable>(_ work: () async throws(PipelineError) -> T) async throws(PipelineError) -> T {
        await queue.acquire()
        do {
            let result = try await work()
            await queue.release()
            return result
        } catch {
            await queue.release()
            throw error
        }
    }

    /// Steps b to d for one capture. `answer` is set for a follow-up.
    private func process(_ id: String, answer: String?) async -> CaptureProblem? {
        guard let current = try? read(id) else { return nil }
        // Already handled by someone else in the meantime? Then there's nothing to do.
        if answer == nil, current.outcome != nil { return nil }
        if answer != nil, current.outcome != .waitingForAnswer { return nil }

        let input = CaptureInput(
            text: current.text, today: now(), timeZone: timeZone, categoryIds: categoryIds(),
            vaultMap: VaultMap.render(folders: VaultMap.scan(vault: config.vault)), vaultGuide: vaultGuide(),
            question: answer == nil ? nil : current.followUp, answer: answer)

        // (b) Ask. If it fails the raw file stays exactly as it is.
        let result: CaptureResult
        do {
            result = try await classifier.classify(input)
        } catch {
            return .classifier(error)
        }

        // (c) Apply, and (d) write down what happened.
        do {
            let update = try apply(result, to: current)
            _ = try record(id, update)
            return nil
        } catch let error as PipelineError {
            return .filing(error.errorDescription ?? "unknown error")
        } catch {
            return .filing(error.localizedDescription)
        }
    }

    /// Does what the result says and returns what to record.
    private func apply(_ result: CaptureResult, to entry: InboxEntry) throws -> InboxUpdate {
        // Not sure enough, or the classifier said so itself: ask the person.
        if result.needsQuestion {
            return InboxUpdate(.waitingForAnswer, [.init("follow_up", result.question)])
        }
        switch result.kind {
        case .task: return try fileTask(result, from: entry)
        case .note: return try fileNote(result, from: entry)
        // Answering from the vault comes later: for now the question stays open.
        case .question: return InboxUpdate(.questionOpen)
        case .unclear: return InboxUpdate(.waitingForAnswer, [.init("follow_up", result.question)])  // (already handled above)
        }
    }

    // MARK: Tasks

    /// A suggested task in the Tasks folder, written by the same code the
    /// board uses, so the board picks it up through its folder watcher.
    /// (The task file has no `from:` link back to the capture: the task
    /// format doesn't write `from` for new tasks. The capture's own file records
    /// which task it made, `task:`.)
    private func fileTask(_ result: CaptureResult, from entry: InboxEntry) throws -> InboxUpdate {
        let task = BoardTask(
            title: result.title, status: .suggested, area: result.area,
            created: TaskFormat.timestamp(now(), timeZone: timeZone), notes: result.body ?? "")
        let saved = try TaskFolder(url: config.tasksURL).save(task)
        // A fingerprint of the file as written: Undo only deletes it if it's still exactly this.
        var fields: [InboxUpdate.Field] = [.init("task", saved.id)]
        if let text = try? String(contentsOf: config.tasksURL.appendingPathComponent(saved.id), encoding: .utf8) {
            fields.append(.init("task_sha", Self.digest(text)))
        }
        return InboxUpdate(.taskSuggested, fields)
    }

    // MARK: Notes

    /// A new note in the folder the classifier suggested, if that folder
    /// passes the path rules, otherwise in the Inbox, with a notice.
    private func fileNote(_ result: CaptureResult, from entry: InboxEntry) throws -> InboxUpdate {
        var notices: [String] = []
        let folder = noteFolder(suggested: result.folder, notices: &notices)

        let stem = TaskFormat.stem(for: result.title)
        // The model's words become a file name through the same rules as task titles.
        // (A name the path rules still don't like is a bug in this chain, not a reason to write anywhere.)
        let path = folder.path.isEmpty ? "\(stem).md" : "\(folder.path)/\(stem).md"
        do { _ = try VaultPath.file(path, reserved: config.reservedFolders) } catch {
            throw PipelineError.io("The note's file name \(path) isn't allowed: \(error.localizedDescription)")
        }

        var fm = Frontmatter()
        fm.set("from", stringNode(link(toRaw: entry.id)))
        fm.set("created", stringNode(TaskFormat.timestamp(now(), timeZone: timeZone)))
        var body = (result.body ?? entry.text)
        if !body.hasSuffix("\n") { body += "\n" }
        let content = "---\n" + (try fm.render()) + "---\n" + body

        let name: String
        do {
            name = try NewFile.create(content, in: folder.url, stem: stem)
        } catch {
            throw PipelineError.io(error.localizedDescription)
        }
        let notePath = folder.path.isEmpty ? name : "\(folder.path)/\(name)"

        var fields: [InboxUpdate.Field] = [.init("note", notePath), .init("note_sha", Self.digest(content))]

        // The daily note gets one line; if that fails the note is still filed.
        let time = Self.clock(now(), timeZone)
        let line = "- \(time) [[\(notePath.dropLast(3))]]"
        do {
            let daily = try appendToDailyNote(line)
            fields.append(.init("daily_note", daily))
            fields.append(.init("daily_line", line))
        } catch {
            notices.append("The note was filed, but the daily note couldn't be updated: \(error.localizedDescription)")
        }
        if !notices.isEmpty { fields.append(.init("notice", notices.joined(separator: " "))) }
        return InboxUpdate(.noteFiled, fields)
    }

    /// The folder for a note: the suggestion if it's allowed, else the Inbox.
    private func noteFolder(suggested: String?, notices: inout [String]) -> (path: String, url: URL) {
        let fallback = (path: config.inboxPath, url: config.vault.appendingPathComponent(config.inboxPath, isDirectory: true))
        guard let suggested else {
            notices.append("The classifier suggested no folder, so the note is in \(config.inboxPath).")
            return fallback
        }
        do {
            let path = try VaultPath.folder(suggested, reserved: config.reservedFolders)
            // Also checks that no link on the way leads out of the vault (or into Tasks).
            let url = try VaultPath.resolve(folder: path, in: config.vault, reserved: config.reservedFolders)
            return (path, url)
        } catch {
            notices.append("The suggested folder “\(suggested)” can't be used (\(error.localizedDescription)), so the note is in \(config.inboxPath).")
            return fallback
        }
    }

    // MARK: Daily note

    /// Adds `line` to today's daily note under `## Captured`. Re-reads the
    /// note right before writing and writes atomically, so a note Obsidian
    /// just saved is extended, not overwritten. A missing note is created
    /// (create-only) with just that section. Returns the note's path.
    private func appendToDailyNote(_ line: String) throws -> String {
        var path = config.dailyNotePath(for: now(), timeZone: timeZone)
        if (try? VaultPath.file(path, reserved: config.reservedFolders)) == nil {
            path = VaultConfig(vault: config.vault).dailyNotePath(for: now(), timeZone: timeZone)
        }
        let file = try VaultPath.resolve(file: path, in: config.vault, reserved: config.reservedFolders)
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A few tries: someone may create or change the note while we work.
        for _ in 0..<3 {
            if FileManager.default.fileExists(atPath: file.path) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                    throw PipelineError.io("\(path) can't be read as text")
                }
                let new = DailyNote.appendingCaptured(line, to: text)
                try TaskFolder(url: folder).writeAtomically(new, to: file)
                return path
            }
            let created = CaptureInbox.createExclusively(Data(DailyNote.appendingCaptured(line, to: "").utf8), at: file)
            if created == 0 { return path }
            if created != EEXIST { throw PipelineError.io(String(cString: strerror(created))) }
        }
        throw PipelineError.io("\(path) kept changing")
    }

    // MARK: Undo

    private func undoNow(_ id: String) throws(PipelineError) -> InboxEntry {
        let current = try read(id)
        var notices: [String] = []

        // 1. A suggested task: delete its file, if it's still a suggestion.
        if let name = current.taskFile {
            let folder = TaskFolder(url: config.tasksURL)
            let file = config.tasksURL.appendingPathComponent(name)
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                // Only if it is byte for byte what we wrote. Moved to Today, edited, or a different
                // task that got the same name after ours was deleted: not ours to delete.
                guard let expected = current.taskDigest, Self.digest(text) == expected else { throw .changedSince("the task “\(name)”") }
                do { try folder.delete(name) } catch { throw .io(error.localizedDescription) }
            }  // gone already: nothing to delete
        }

        // 2. A filed note: delete it if it's byte for byte what we wrote, then its daily line.
        if let notePath = current.notePath {
            let file: URL
            do { file = try VaultPath.resolve(file: notePath, in: config.vault, reserved: config.reservedFolders) } catch {
                throw .io("The recorded note path isn't usable: \(error.localizedDescription)")
            }
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                guard let expected = current.noteDigest, Self.digest(text) == expected else { throw .changedSince("the note “\(notePath)”") }
                do { try FileManager.default.removeItem(at: file) } catch { throw .io(error.localizedDescription) }
            }
            if let message = removeDailyLine(current) { notices.append(message) }
        }

        var fields: [InboxUpdate.Field] = []
        if !notices.isEmpty { fields.append(.init("notice", notices.joined(separator: " "))) }
        return try record(id, InboxUpdate(.skipped, fields))
    }

    /// Takes the line this capture added out of the daily note, if it's still there as written.
    /// Returns a message for the person when it can't.
    private func removeDailyLine(_ entry: InboxEntry) -> String? {
        guard let daily = entry.dailyNote, let line = entry.dailyLine else { return nil }
        // The raw file is a file anyone can edit, so the recorded path is checked: it must be
        // the daily note of the day the capture was made (same folder and name format), and the
        // line must link to the note we filed. Otherwise the daily note is left as it is. (If
        // the settings changed since, or the capture crossed midnight, that means the line stays.)
        guard let captured = entry.captured.flatMap({ Self.date(fromStamp: $0, timeZone) }),
            daily == config.dailyNotePath(for: captured, timeZone: timeZone), let note = entry.notePath,
            line.contains("[[\(note.dropLast(3))]]")
        else { return "The daily note line was left as it is: it isn't where this capture's day note would be." }
        guard let file = try? VaultPath.resolve(file: daily, in: config.vault, reserved: config.reservedFolders),
            let text = try? String(contentsOf: file, encoding: .utf8)
        else { return "The daily note \(daily) couldn't be read, so its line was left." }
        guard let new = DailyNote.removingLine(line, from: text) else {
            return "The line in \(daily) was changed, so it was left as it is."
        }
        do {
            try TaskFolder(url: file.deletingLastPathComponent()).writeAtomically(new, to: file)
            return nil
        } catch {
            return "The line in \(daily) couldn't be removed: \(error.localizedDescription)"
        }
    }

    // MARK: Reading and recording

    private func rawURL(_ id: String) throws(PipelineError) -> URL {
        // An id is a plain file name in the Inbox (like a task id, task format 5.9).
        guard !id.isEmpty, !id.contains("/"), !TaskFormat.isIgnored(id) else { throw .notFound(id) }
        return config.inbox.url.appendingPathComponent(id)
    }

    private func read(_ id: String) throws(PipelineError) -> InboxEntry {
        let url = try rawURL(id)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw .notFound(id) }
        return InboxEntry.parse(id: id, text: text)
    }

    /// The entry now (or an empty shell if the file vanished).
    private func entry(_ id: String) -> InboxEntry {
        (try? read(id)) ?? InboxEntry(id: id, text: "")
    }

    /// Writes an update into the raw file. Re-reads the file first, and
    /// changes only the frontmatter, atomically.
    @discardableResult
    private func record(_ id: String, _ update: InboxUpdate) throws(PipelineError) -> InboxEntry {
        let url = try rawURL(id)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw .notFound(id) }
        guard let new = InboxEntry.applying(update.clearingTheRest(), to: text) else {
            throw .io("The capture \(id) has broken frontmatter, so its outcome wasn't recorded. Fix it in Obsidian.")
        }
        do {
            try TaskFolder(url: config.inbox.url).writeAtomically(new, to: url)
        } catch {
            throw .io(error.localizedDescription)
        }
        notify(id)
        return InboxEntry.parse(id: id, text: new)
    }

    private func notify(_ id: String) {
        if let onChange, let e = try? read(id) { onChange(e) }
    }

    // MARK: Small helpers

    /// `[[Notes/Inbox/2026-11-26 13-05-22]]`: a link back to the raw capture.
    private func link(toRaw id: String) -> String {
        "[[\(config.inboxPath)/\(id.hasSuffix(".md") ? String(id.dropLast(3)) : id)]]"
    }

    private func vaultGuide() -> String? {
        try? String(contentsOf: config.vault.appendingPathComponent("_vault-guide.md"), encoding: .utf8)
    }

    /// A `YYYY-MM-DDTHH:MM` stamp back into a date.
    static func date(fromStamp stamp: String, _ timeZone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: stamp)
    }

    /// `13:05`
    static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        String(TaskFormat.timestamp(date, timeZone: timeZone).suffix(5))
    }

    /// A fingerprint of a text (SHA-256), to tell later whether it changed.
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
