// Loading and saving the tasks in one folder (spec 1, 4.2 and 5).
// A Swift port of `load_all`, `save`, `rename`, `complete` and `delete` in
// src-tauri/src/tasks.rs.
//
// This is plain file access. Coordinating with iCloud (NSFileCoordinator,
// files that aren't downloaded yet) comes on top of it later, in the app's
// vault store, so these rules stay easy to test with a temporary folder.

import Foundation

/// What can go wrong when changing task files.
///
/// Swift note: `LocalizedError` with `errorDescription` gives each error a
/// sentence that can be shown to the user as it is.
public enum TaskFileError: Error, Equatable, LocalizedError {
    case notATaskFile(String)
    case notFound(String)
    case invalidFrontmatter(String)
    case invalidSettings
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSettings:
            "\(TaskFolder.settingsFile) in the Tasks folder isn't valid JSON, so this device's categories are used. Fix the file or delete it."
        case .notATaskFile(let id): "Not a task file: \(id)"
        case .notFound(let id): "Task file not found: \(id)"
        case .invalidFrontmatter(let id):
            "Not saving \(id): its frontmatter isn't valid YAML. Fix it in Obsidian first."
        case .io(let message): message
        }
    }
}

/// The Tasks folder, e.g. `<vault>/Notes/Tasks`.
public struct TaskFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    // MARK: - Reading

    /// Every task in the folder. Only files directly inside it count, and
    /// files without an `order` go on top (spec 4.2).
    public func loadAll() throws(TaskFileError) -> [BoardTask] {
        let fm = FileManager.default
        let names: [String]
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            names = try fm.contentsOfDirectory(atPath: url.path)
        } catch {
            throw .io(error.localizedDescription)
        }
        var tasks: [BoardTask] = []
        for name in names where !TaskFormat.isIgnored(name) {
            let file = url.appendingPathComponent(name)
            // `isDirectory` is filled in by `fileExists` (an "inout" pointer, in C style).
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                // Not valid UTF-8 → skipped, not an error (spec 1).
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            var task = TaskFormat.parse(id: name, text: text)
            if task.status == .done {
                let modified = (try? fm.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
                task.done = TaskFormat.doneTime(task.done, modified: modified.map { TaskFormat.timestamp($0) })
            }
            tasks.append(task)
        }
        // Tasks without an order: the smallest order of all, minus 1024 (or 0).
        let top = tasks.compactMap(\.order).min().map { $0 - 1024 } ?? 0
        for i in tasks.indices where tasks[i].order == nil {
            tasks[i].order = top
        }
        return tasks
    }

    public func load(_ id: String) throws(TaskFileError) -> BoardTask {
        guard let task = try loadAll().first(where: { $0.id == id }) else { throw .notFound(id) }
        return task
    }

    // MARK: - Writing

    /// Saves a task (spec 5.1 and 5.5). A new task (empty id) gets a file
    /// named after its title. An existing file keeps its other fields and,
    /// unless the checklist or notes changed, its body byte-for-byte.
    @discardableResult
    public func save(_ task: BoardTask) throws(TaskFileError) -> BoardTask {
        var task = task
        try createFolder()
        let isNew = task.id.isEmpty
        if isNew {
            task.id = freeName(for: task.title, current: nil)
        }
        let file = try path(of: task.id)

        // Start from what's on disk right now: another program may have changed it.
        var fm = Frontmatter()
        var oldBody: String? = nil
        if !isNew, let text = try? String(contentsOf: file, encoding: .utf8) {
            let (yaml, body) = splitFrontmatter(text)
            if let yaml {
                do {
                    fm = try Frontmatter.parse(yaml)
                } catch {
                    throw .invalidFrontmatter(task.id)
                }
            }
            oldBody = body
        }

        // The fields this app owns. `set` keeps an existing field in its place.
        fm.set("status", stringNode(task.status.rawValue))
        fm.set("area", stringNode(task.area))
        fm.remove("colour")  // the old name of `area`
        if let order = task.order {
            fm.set("order", numberNode(order))
        }
        if task.created != nil || isNew {
            fm.set("created", task.created.map(stringNode) ?? nullNode())
        }
        fm.set("done", task.done.map(stringNode) ?? nullNode())
        if task.focus {
            fm.set("focus", .scalar(.init("true", .implicit, .plain)))
        } else {
            fm.remove("focus")
        }
        if isNew && fm["project"] == nil {
            fm.set("project", task.project.map(stringNode) ?? nullNode())
        }
        TaskFormat.applyTitle(&fm, id: task.id, title: task.title)

        // Keep the body untouched unless the checklist or notes actually changed.
        let body: String
        if let oldBody, TaskFormat.parseBody(oldBody) == (task.items, task.notes.trimmingCharacters(in: .whitespacesAndNewlines)) {
            body = oldBody
        } else {
            body = TaskFormat.renderBody(items: task.items, notes: task.notes)
        }

        let text = "---\n" + (try render(fm)) + "---\n" + body
        try writeAtomically(text, to: file)
        return reparse(id: task.id, text: text, order: task.order)
    }

    /// Renames the task's file to fit a new title (spec 5.7).
    @discardableResult
    public func rename(_ id: String, to title: String, order: Double?) throws(TaskFileError) -> BoardTask {
        let from = try path(of: id)
        let name = freeName(for: title, current: id)
        let to = try path(of: name)
        if name != id {
            do {
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                throw .io(error.localizedDescription)
            }
        }
        var content: String
        do {
            content = try String(contentsOf: to, encoding: .utf8)
        } catch {
            throw .io(error.localizedDescription)
        }
        let (yaml, body) = splitFrontmatter(content)
        // No frontmatter yet → an empty one (only written if `title:` is needed).
        // Broken YAML → leave the content alone; the title is then the file name.
        if var fm = try? Frontmatter.parse(yaml ?? "") {
            var changed = false
            // A `title:` that belonged to the *old* name was ours: drop it first.
            if let old = fieldText(fm["title"]), TaskFormat.titleMatchesFile(old, id: id) {
                fm.remove("title")
                changed = true
            }
            // Not `changed || …`: `||` would skip `applyTitle` once `changed` is true.
            let titleChanged = TaskFormat.applyTitle(&fm, id: name, title: title.trimmingCharacters(in: .whitespaces))
            if changed || titleChanged {
                let newText = "---\n" + (try render(fm)) + "---\n" + body
                try writeAtomically(newText, to: to)
                content = newText
            }
        }
        return reparse(id: name, text: content, order: order)
    }

    /// Marks a task done at `now` and ends its focus (spec 5.8). Only the
    /// task's own file is written, never a daily note.
    @discardableResult
    public func complete(_ id: String, now: String) throws(TaskFileError) -> BoardTask {
        var task = try load(id)
        task.status = .done
        task.focus = false
        task.done = now
        return try save(task)
    }

    /// Deletes the task's file for good.
    public func delete(_ id: String) throws(TaskFileError) {
        do {
            try FileManager.default.removeItem(at: try path(of: id))
        } catch let error as TaskFileError {
            throw error
        } catch {
            throw .io(error.localizedDescription)
        }
    }

    /// Writes a deleted task's file back exactly as it was (Undo). If its name
    /// was taken in the meantime, it gets a free one. Returns the name used.
    @discardableResult
    public func restore(_ id: String, text: String) throws(TaskFileError) -> String {
        _ = try path(of: id)
        try createFolder()
        let taken = FileManager.default.fileExists(atPath: url.appendingPathComponent(id).path)
        let name = taken ? freeName(for: String(id.dropLast(3)), current: nil) : id
        try writeAtomically(text, to: try path(of: name))
        return name
    }

    // MARK: - Helpers

    /// A free file name for `title`: `Name.md`, else `Name (2).md`, `Name (3).md`…
    /// `current` (the task's own file when renaming) doesn't count as taken,
    /// compared without capitals: macOS sees `Fix.md` and `fix.md` as one file.
    func freeName(for title: String, current: String?) -> String {
        let stem = TaskFormat.stem(for: title)
        var n = 1
        while true {
            let name = n == 1 ? "\(stem).md" : "\(stem) (\(n)).md"
            let isSelf = current?.lowercased() == name.lowercased()
            if isSelf || (!TaskFormat.isIgnored(name) && !FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)) {
                return name
            }
            n += 1
        }
    }

    /// Refuses ids like `../../.ssh/config.md` (spec 5.9): a task may only
    /// touch plain files directly inside the folder.
    func path(of id: String) throws(TaskFileError) -> URL {
        let single = !id.isEmpty && !id.contains("/") && id != "." && id != ".."
        guard single, !TaskFormat.isIgnored(id) else { throw .notATaskFile(id) }
        return url.appendingPathComponent(id)
    }

    func createFolder() throws(TaskFileError) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .io(error.localizedDescription)
        }
    }

    private func render(_ fm: Frontmatter) throws(TaskFileError) -> String {
        do {
            return try fm.render()
        } catch {
            throw .io("Couldn't write the frontmatter: \(error)")
        }
    }

    /// Writes `.<name>.tmp`, then renames it over the file (spec 5.6), so
    /// nobody ever reads a half-written task. `rename` is the system call that
    /// does this in one step; Foundation's `moveItem` refuses to overwrite.
    func writeAtomically(_ text: String, to file: URL) throws(TaskFileError) {
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).tmp")
        do {
            try Data(text.utf8).write(to: tmp)
        } catch {
            throw .io(error.localizedDescription)
        }
        if Darwin.rename(tmp.path, file.path) != 0 {
            let message = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: tmp)
            throw .io(message)
        }
    }

    /// `parse`, but keeping the order we already know (for files without one).
    private func reparse(id: String, text: String, order: Double?) -> BoardTask {
        var task = TaskFormat.parse(id: id, text: text)
        if task.order == nil {
            task.order = order ?? 0
        }
        return task
    }
}
