// Reading one task file, and the title and file-name rules.
// A Swift port of src-tauri/src/tasks.rs; the spec is docs/task-format.md.
//
// Swift note: an `enum` with no cases is a common way to group functions under
// one name (`TaskFormat.parse(…)`). It can't be created, it's only a namespace.

import Foundation

public enum TaskFormat {
    // MARK: - Reading (spec 2 and 3)

    /// Parses one file. `id` is its file name. Never fails: broken YAML is read
    /// as "no fields", so the task still shows up (spec 2.2).
    public static func parse(id: String, text: String) -> BoardTask {
        let (yaml, body) = splitFrontmatter(text)
        let fm = yaml.flatMap { try? Frontmatter.parse($0) } ?? Frontmatter()
        let (items, notes) = parseBody(body)

        var status = TaskStatus.backlog
        if case .scalar(let s)? = fm["status"], case .string(let name) = YAMLValue(s) {
            status = TaskStatus(rawValue: name) ?? .backlog
        }
        var focus = false
        if case .scalar(let s)? = fm["focus"] {
            focus = YAMLValue(s) == .bool(true)
        }
        var order: Double? = nil
        if case .scalar(let s)? = fm["order"], case .number(let d, _) = YAMLValue(s), d.isFinite {
            order = d
        }

        return BoardTask(
            id: id,
            title: titleOf(id: id, field: fieldText(fm["title"])),
            status: status,
            // `colour` is the old name of `area`. `??` means "if that's nil, use this".
            area: fieldText(fm["area"]) ?? fieldText(fm["colour"]) ?? "personal",
            focus: focus,
            order: order,
            created: fieldText(fm["created"]),
            done: fieldText(fm["done"]),
            project: fieldText(fm["project"]),
            from: fieldText(fm["from"]),
            isPrivate: body.contains("#private"),
            items: items,
            notes: notes
        )
    }

    /// Splits the body into checklist items and the remaining notes (spec 3.1).
    static func parseBody(_ body: String) -> (items: [ChecklistItem], notes: String) {
        var items: [ChecklistItem] = []
        var notes: [String] = []
        for line in lines(of: body) {
            let trimmed = String(line.drop { $0.isWhitespace })
            if trimmed.hasPrefix("- [ ] ") {
                items.append(ChecklistItem(text: String(trimmed.dropFirst(6)), done: false))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                items.append(ChecklistItem(text: String(trimmed.dropFirst(6)), done: true))
            } else {
                notes.append(line)
            }
        }
        return (items, notes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Lines split on `\n`, each without a trailing `\r`, like Rust's `lines()`.
    /// Splits the Unicode scalars, not the `String`: Swift sees `\r\n` as one
    /// character, so splitting a String on "\n" would miss Windows line breaks.
    static func lines(of text: String) -> [String] {
        if text.isEmpty { return [] }
        var parts = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map {
            var line = String(String.UnicodeScalarView($0))
            if line.unicodeScalars.last == "\r" { line.unicodeScalars.removeLast() }
            return line
        }
        // A final line break doesn't start another (empty) line.
        if text.unicodeScalars.last == "\n" { parts.removeLast() }
        return parts
    }

    // MARK: - Titles and file names (spec 4.1)

    /// The file stem a title gets: bad characters become `-`, at most 80
    /// characters, no dots or spaces at the ends, never empty.
    ///
    /// Everything here works on `unicodeScalars`, because the spec counts 80
    /// Unicode scalars like Rust does. A Swift `Character` can be several
    /// scalars (👩‍💻 is three), so `title.prefix(80)` would count differently.
    public static func stem(for title: String) -> String {
        let bad: Set<Unicode.Scalar> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]
        let cleaned = title.unicodeScalars.map { c -> Unicode.Scalar in
            bad.contains(c) || c.properties.generalCategory == .control ? "-" : c
        }
        let isSpace = { (c: Unicode.Scalar) in c.properties.isWhitespace }
        let short = Array(trim(cleaned[...], where: isSpace).prefix(80))
        let stem = trim(short[...], where: { $0 == "." || isSpace($0) })
        return stem.isEmpty ? "Untitled" : String(String.UnicodeScalarView(stem))
    }

    /// Drops scalars matching `test` from both ends.
    private static func trim(_ s: ArraySlice<Unicode.Scalar>, where test: (Unicode.Scalar) -> Bool) -> ArraySlice<Unicode.Scalar> {
        var s = s
        while let first = s.first, test(first) { s.removeFirst() }
        while let last = s.last, test(last) { s.removeLast() }
        return s
    }

    /// `Fix token (2).md` → `Fix token (2)`.
    static func stemOf(_ id: String) -> String {
        id.hasSuffix(".md") ? String(id.dropLast(3)) : id
    }

    /// `Fix token (2)` → `Fix token`: the stem without a clash counter.
    static func withoutCounter(_ stem: String) -> String {
        guard let open = stem.range(of: " (", options: .backwards), stem.hasSuffix(")") else { return stem }
        let digits = stem[open.upperBound..<stem.index(before: stem.endIndex)]
        if !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return String(stem[..<open.lowerBound])
        }
        return stem
    }

    /// Does a `title:` field belong to this file? Only if this file name is
    /// what that title would give. Renamed in Obsidian → the file name wins.
    static func titleMatchesFile(_ title: String, id: String) -> Bool {
        let stem = stem(for: title)
        return stem == stemOf(id) || stem == withoutCounter(stemOf(id))
    }

    /// The title to show: `title:` if it belongs to this file, else the file name.
    static func titleOf(id: String, field: String?) -> String {
        if let field, titleMatchesFile(field, id: id) {
            return field
        }
        return stemOf(id)
    }

    /// Writes or removes `title:` (spec 5.3). Returns true if anything changed.
    @discardableResult
    static func applyTitle(_ fm: inout Frontmatter, id: String, title: String) -> Bool {
        if title != stemOf(id) && title != withoutCounter(stemOf(id)) {
            if fieldText(fm["title"]) == title { return false }
            fm.set("title", stringNode(title))
            return true
        }
        // The file name says it all. Remove a `title:` only if it's ours.
        if let current = fieldText(fm["title"]), titleMatchesFile(current, id: id) {
            return fm.remove("title")
        }
        return false
    }

    // MARK: - Files that aren't tasks (spec 1)

    /// Hidden files (our `.tmp` files, iCloud's `.icloud` placeholders), README.md and non-`.md` files.
    public static func isIgnored(_ name: String) -> Bool {
        name.hasPrefix(".") || name.lowercased() == "readme.md" || !name.hasSuffix(".md")
    }

    // MARK: - Done time (spec 4.3)

    /// A done task without a time borrows the file's last-modified time
    /// (`modified`, same `YYYY-MM-DDTHH:MM` shape). Only how it's shown.
    static func doneTime(_ done: String?, modified: String?) -> String? {
        guard let done else { return modified }
        if let modified, done.count == 10, modified.hasPrefix(done) {
            return modified
        }
        return done
    }

    /// `2026-11-22T09:40` in local time: the shape of `created:` and `done:`.
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        // `en_US_POSIX` keeps the digits Western and the format fixed, whatever
        // language and calendar the phone is set to.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: date)
    }

    // MARK: - Writing a body (spec 5.4)

    /// Checklist first, then a blank line, then the notes.
    static func renderBody(items: [ChecklistItem], notes: String) -> String {
        var out = ""
        for item in items {
            out += "- [\(item.done ? "x" : " ")] \(item.text)\n"
        }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if !out.isEmpty { out += "\n" }
            out += trimmed + "\n"
        }
        return out
    }
}
