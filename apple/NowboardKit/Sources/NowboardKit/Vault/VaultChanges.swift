// Changing notes the person already has, safely (docs/vault-changes.md).
//
// The rule behind everything here: nothing is lost. Before a note is changed or
// moved, the original goes into a hidden history folder. Every change is written
// into an append-only log. Any change can be undone, as long as the files it
// touched are still as the change left them. And there is no way to delete.

import CryptoKit
import Foundation

public enum ChangeError: Error, Equatable, LocalizedError {
    /// The operation isn't allowed; the sentence says why. Nothing was changed.
    case refused(String)
    /// Undo refused: this file was changed after the change, so it isn't ours to put back.
    case changedSince(String)
    case unknownChange(String)
    case alreadyUndone(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let why): "Not done: \(why)"
        case .changedSince(let path): "Not undone: \(path) was changed after, so it was left alone."
        case .unknownChange(let id): "No change with the id \(id)."
        case .alreadyUndone(let id): "The change \(id) was already undone."
        case .io(let why): why
        }
    }
}

/// One change as written in the log.
public struct ChangeRecord: Codable, Equatable, Sendable {
    /// A file the change touched.
    public struct Touched: Codable, Equatable, Sendable {
        /// Where it is now.
        public var path: String
        /// The original, inside the history folder of this change (`.nowboard/history/<id>/…`).
        public var history: String
        /// The SHA-256 of its text as the change left it (for Undo to check).
        public var afterSha: String
    }

    public var id: String
    /// Local time, `YYYY-MM-DDTHH:MM:SS`.
    public var time: String
    public var operation: VaultOperation
    /// For a move or rename: where the note was.
    public var from: String?
    public var files: [Touched]
    /// How many links in other notes were updated, and how many were left because they could mean another note.
    public var linksChanged: Int
    public var linksAmbiguous: Int
    /// Filled in when the log is read: whether an undo was logged for it.
    public var undone: Bool = false

    enum CodingKeys: String, CodingKey { case id, time, operation, from, files, linksChanged, linksAmbiguous }
}

/// Swift note: `@unchecked Sendable` = "safe to use from background threads, I promise". It holds only
/// constants (the config and a clock), and each change works on files, so a change on a background thread
/// is fine. The app makes one change at a time.
public final class VaultChanges: @unchecked Sendable {
    public let config: VaultConfig
    private let now: @Sendable () -> Date

    /// The hidden folder (Obsidian ignores folders that start with a dot).
    public static let folderName = ".nowboard"
    private var root: URL { config.vault.appendingPathComponent(Self.folderName, isDirectory: true) }
    private var logURL: URL { root.appendingPathComponent("changes.jsonl") }
    private var historyURL: URL { root.appendingPathComponent("history", isDirectory: true) }

    public init(config: VaultConfig, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.now = now
    }

    // MARK: - Reading the vault

    /// Every note in the vault (vault-relative paths ending in `.md`), without hidden folders and files and
    /// without links to other places. At most `limit`.
    public func allNotes(limit: Int = 20_000) -> [String] {
        var found: [String] = []
        let root = config.vault.resolvingSymlinksInPath().standardizedFileURL
        func walk(_ folder: URL, prefix: String) {
            guard found.count < limit, let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { continue }
                let path = prefix + entry.lastPathComponent
                if values?.isDirectory == true {
                    walk(entry, prefix: path + "/")
                } else if entry.pathExtension == "md" {
                    found.append(path)
                }
            }
        }
        walk(root, prefix: "")
        return found
    }

    private func read(_ path: String) -> String? {
        try? String(contentsOf: config.vault.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Is it allowed?

    /// What an operation would do, after every check. Throws `.refused` with the reason otherwise.
    struct Plan {
        var operation: VaultOperation
        /// The note now, and (for a move) where it goes.
        var source: String
        var destination: String?
    }

    func plan(_ operation: VaultOperation) throws(ChangeError) -> Plan {
        // The source: a normal path, not in the Tasks folder, an existing note.
        let source: String
        do { source = try VaultPath.file(operation.path, reserved: config.reservedFolders) } catch {
            throw .refused("the path “\(operation.path)” isn't allowed (\(error.localizedDescription))")
        }
        do { _ = try VaultPath.resolve(file: source, in: config.vault, reserved: config.reservedFolders) } catch {
            throw .refused("the path “\(source)” isn't allowed (\(error.localizedDescription))")
        }
        guard source != VaultGuide.fileName else { throw .refused("the vault guide is not changed this way") }
        guard let text = read(source) else { throw .refused("“\(source)” doesn't exist or isn't text") }
        // A raw capture is the record of what was typed: never moved or edited.
        guard InboxEntry.parse(id: source, text: text).captured == nil else {
            throw .refused("“\(source)” is a saved capture; those are never changed")
        }

        switch operation.kind {
        case .move, .rename:
            let destination: String
            if operation.kind == .move {
                guard let to = operation.to else { throw .refused("no destination") }
                destination = to
            } else {
                guard let name = operation.name else { throw .refused("no new name") }
                let stem = TaskFormat.stem(for: name)
                let folder = source.split(separator: "/").dropLast().joined(separator: "/")
                destination = folder.isEmpty ? "\(stem).md" : "\(folder)/\(stem).md"
            }
            let to: String
            do { to = try VaultPath.file(destination, reserved: config.reservedFolders) } catch {
                throw .refused("the destination “\(destination)” isn't allowed (\(error.localizedDescription))")
            }
            do { _ = try VaultPath.resolve(file: to, in: config.vault, reserved: config.reservedFolders) } catch {
                throw .refused("the destination “\(to)” isn't allowed (\(error.localizedDescription))")
            }
            guard to != VaultGuide.fileName else { throw .refused("the vault guide's name is taken") }
            guard to.lowercased() != source.lowercased() else { throw .refused("it is already there") }
            // Never overwrite. (`fileExists` follows the file system's own rules: on a Mac, capitals don't matter.)
            guard !FileManager.default.fileExists(atPath: config.vault.appendingPathComponent(to).path) else {
                throw .refused("“\(to)” already exists")
            }
            return Plan(operation: operation, source: source, destination: to)

        case .append:
            guard let add = operation.text?.trimmingCharacters(in: .whitespacesAndNewlines), !add.isEmpty else { throw .refused("nothing to add") }
            guard add.count <= 4000, !add.contains("\u{0}") else { throw .refused("the text to add is too long or not text") }
            return Plan(operation: operation, source: source, destination: nil)

        case .retitle:
            guard let title = operation.title, !title.trimmingCharacters(in: .whitespaces).isEmpty, title.count <= 200, !title.contains("\n"),
                !title.contains("\r")
            else {
                throw .refused("the new title is empty, too long or not one line")
            }
            guard Self.retitled(text, to: title) != nil else { throw .refused("“\(source)” has no first heading to change") }
            return Plan(operation: operation, source: source, destination: nil)
        }
    }

    /// Checks an operation without doing anything: nil if it is allowed, otherwise the reason.
    public func problem(with operation: VaultOperation) -> String? {
        do {
            _ = try plan(operation)
            return nil
        } catch {
            if case .refused(let why) = error { return why }
            return error.localizedDescription
        }
    }

    // MARK: - Text changes (pure)

    /// The text with its first `# ` heading (outside frontmatter and code) set to `title`, or nil if there is none.
    static func retitled(_ text: String, to title: String) -> String? {
        var lines: [(body: String, end: String)] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                if current.last == "\r" {
                    current.removeLast()
                    lines.append((String(current), "\r\n"))
                } else {
                    lines.append((String(current), "\n"))
                }
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { lines.append((String(current), "")) }

        var i = 0
        // Skip frontmatter.
        if lines.first?.body == "---", let close = (1..<lines.count).first(where: { lines[$0].body == "---" }) { i = close + 1 }
        var fence: Character?
        while i < lines.count {
            let body = lines[i].body
            let trimmed = body.drop { $0 == " " }
            if let marker = trimmed.first, marker == "`" || marker == "~", trimmed.prefix(3).allSatisfy({ $0 == marker }) {
                fence = fence == marker ? nil : (fence ?? marker)
            } else if fence == nil, body.hasPrefix("# ") {
                lines[i].body = "# " + title
                return lines.map { $0.body + $0.end }.joined()
            }
            i += 1
        }
        return nil
    }

    /// The text with `addition` added at the end (after a blank line), ending with a line break.
    static func appended(_ text: String, _ addition: String) -> String {
        var result = text
        if let last = result.unicodeScalars.last, last != "\n" { result += "\n" }
        if !result.isEmpty { result += "\n" }
        return result + addition.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - Doing it

    /// Checks and does one operation: the originals go to the history folder first, links to a moved note
    /// are updated, and the change is logged. Returns the log record.
    @discardableResult
    public func apply(_ operation: VaultOperation) throws(ChangeError) -> ChangeRecord {
        let plan = try plan(operation)
        let id = makeID()
        let fm = FileManager.default
        var touched: [ChangeRecord.Touched] = []
        var linksChanged = 0, linksAmbiguous = 0

        guard let original = read(plan.source) else { throw .refused("“\(plan.source)” can't be read") }

        // What each file will contain afterwards, worked out before anything is written.
        // (path now, original text, new text, where it will be)
        var edits: [(path: String, original: String, new: String, finalPath: String)] = []
        switch operation.kind {
        case .move, .rename:
            let destination = plan.destination!
            let notes = allNotes()
            // The moved note's own text: its links to itself must follow too.
            let own = WikiLinks.rewrite(original, moving: plan.source, to: destination, notes: notes)
            linksChanged += own.changed
            linksAmbiguous += own.ambiguous
            edits.append((plan.source, original, own.text, destination))
            // Every other note that links to it.
            let name = ((plan.source as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            for note in notes where note.lowercased() != plan.source.lowercased() {
                guard let text = read(note), text.contains("[["), text.lowercased().contains(name) else { continue }
                let result = WikiLinks.rewrite(text, moving: plan.source, to: destination, notes: notes)
                linksAmbiguous += result.ambiguous
                if result.changed > 0 {
                    linksChanged += result.changed
                    edits.append((note, text, result.text, note))
                }
            }
        case .append:
            edits.append((plan.source, original, Self.appended(original, operation.text ?? ""), plan.source))
        case .retitle:
            guard let new = Self.retitled(original, to: operation.title ?? "") else { throw .refused("no heading to change") }
            edits.append((plan.source, original, new, plan.source))
        }
        // Nothing may end up empty: a change that would leave a note empty is refused.
        for edit in edits where edit.original.contains(where: { !$0.isWhitespace }) && !edit.new.contains(where: { !$0.isWhitespace }) {
            throw .refused("it would leave “\(edit.path)” empty")
        }

        // 1. The originals, into the history folder (create-only).
        for edit in edits {
            let target = historyURL.appendingPathComponent(id).appendingPathComponent(edit.path)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(edit.original.utf8).write(to: target, options: .withoutOverwriting)
            } catch {
                throw .io("Couldn't save the original of \(edit.path): \(error.localizedDescription)")
            }
        }

        // 2. The change itself.
        do {
            if operation.kind == .move || operation.kind == .rename {
                let to = config.vault.appendingPathComponent(plan.destination!)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                // `moveItem` refuses if something is there: nothing is ever overwritten.
                try fm.moveItem(at: config.vault.appendingPathComponent(plan.source), to: to)
            }
            for edit in edits {
                let url = config.vault.appendingPathComponent(edit.finalPath)
                if edit.new != edit.original || edit.path != edit.finalPath {
                    // Re-read right before writing: if the note changed meanwhile, stop (what we move stays moved).
                    if let now = try? String(contentsOf: url, encoding: .utf8), now != edit.original {
                        throw ChangeError.io("“\(edit.finalPath)” changed while it was being updated, so it was left alone")
                    }
                    try TaskFolder(url: url.deletingLastPathComponent()).writeAtomically(edit.new, to: url)
                }
                touched.append(.init(path: edit.finalPath, history: edit.path, afterSha: Self.sha(edit.new)))
            }
        } catch {
            // Something failed half way: put everything back from the originals, so no note is left
            // moved without its links updated. (Best effort: the originals are all in the history folder.)
            rollback(edits: edits.map { ($0.path, $0.finalPath) }, id: id)
            if let error = error as? ChangeError { throw error }
            throw .io(error.localizedDescription)
        }

        // 3. The log.
        let record = ChangeRecord(
            id: id, time: Self.timestamp(now()), operation: operation, from: plan.destination == nil ? nil : plan.source, files: touched,
            linksChanged: linksChanged, linksAmbiguous: linksAmbiguous)
        try append(toLog: ["type": "change", "record": record])
        return record
    }

    /// Restores every file of a change that failed half way from the history folder.
    private func rollback(edits: [(path: String, finalPath: String)], id: String) {
        let fm = FileManager.default
        for edit in edits {
            let originalURL = historyURL.appendingPathComponent(id).appendingPathComponent(edit.path)
            guard let original = try? String(contentsOf: originalURL, encoding: .utf8) else { continue }
            let back = config.vault.appendingPathComponent(edit.path)
            let moved = config.vault.appendingPathComponent(edit.finalPath)
            if edit.path != edit.finalPath, fm.fileExists(atPath: moved.path), !fm.fileExists(atPath: back.path) {
                try? fm.moveItem(at: moved, to: back)
            }
            try? TaskFolder(url: back.deletingLastPathComponent()).writeAtomically(original, to: back)
        }
    }

    // MARK: - Undo

    /// Puts a change back, if every file it touched is still exactly as the change left it. Nothing is
    /// deleted: the moved note goes back, and the originals come out of the history folder.
    @discardableResult
    public func undo(_ id: String) throws(ChangeError) -> ChangeRecord {
        guard id.wholeMatch(of: /[0-9]{8}-[0-9]{6}-[0-9a-f]{4}/) != nil else { throw .unknownChange(id) }
        let all = records()
        guard let record = all.first(where: { $0.id == id }) else { throw .unknownChange(id) }
        guard !record.undone else { throw .alreadyUndone(id) }
        let fm = FileManager.default

        // Everything must be as we left it, or nothing is changed.
        for file in record.files {
            guard let text = read(file.path), Self.sha(text) == file.afterSha else { throw .changedSince(file.path) }
        }
        if let from = record.from, fm.fileExists(atPath: config.vault.appendingPathComponent(from).path) {
            throw .refused("“\(from)” exists again, so the note can't go back there")
        }

        do {
            for file in record.files {
                let url = config.vault.appendingPathComponent(file.path)
                let originalURL = historyURL.appendingPathComponent(id).appendingPathComponent(file.history)
                guard let original = try? String(contentsOf: originalURL, encoding: .utf8) else {
                    throw ChangeError.io("The saved original of \(file.history) is missing, so the change can't be undone.")
                }
                let back = config.vault.appendingPathComponent(file.history)
                if file.path != file.history {
                    try fm.createDirectory(at: back.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: url, to: back)
                }
                try TaskFolder(url: back.deletingLastPathComponent()).writeAtomically(original, to: back)
            }
        } catch let error as ChangeError {
            throw error
        } catch {
            throw .io(error.localizedDescription)
        }
        try append(toLog: ["type": "undo", "undoes": record.id, "time": Self.timestamp(now())])
        var done = record
        done.undone = true
        return done
    }

    // MARK: - The log

    /// All changes, newest first. Each says whether it was undone.
    public func records() -> [ChangeRecord] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        var records: [ChangeRecord] = []
        var undone = Set<String>()
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "change":
                if let recordObject = object["record"], let recordData = try? JSONSerialization.data(withJSONObject: recordObject),
                    let record = try? JSONDecoder().decode(ChangeRecord.self, from: recordData)
                {
                    records.append(record)
                }
            case "undo":
                if let id = object["undoes"] as? String { undone.insert(id) }
            default: break
            }
        }
        return records.reversed().map { var r = $0; r.undone = undone.contains(r.id); return r }
    }

    /// Adds one line to the log. The log is only ever added to.
    private func append(toLog entry: [String: Any]) throws(ChangeError) {
        var object = entry
        if let record = entry["record"] as? ChangeRecord,
            let data = try? JSONEncoder().encode(record), let json = try? JSONSerialization.jsonObject(with: data)
        {
            object["record"] = json
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { throw .io("Couldn't write the log") }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw .io(error.localizedDescription)
        }
        // `O_APPEND`: every write goes to the end of the file, whatever else is writing.
        let fd = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { throw .io("Couldn't open the log: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        let line = data + Data("\n".utf8)
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
        guard written == line.count else { throw .io("Couldn't write the log") }
    }

    // MARK: - Small helpers

    private func makeID() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = String(format: "%04x", UInt16.random(in: 0...UInt16.max))
        return "\(f.string(from: now()))-\(suffix)"
    }

    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    static func sha(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
