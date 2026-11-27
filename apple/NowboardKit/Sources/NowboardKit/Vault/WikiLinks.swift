// Moving or renaming a note without breaking the links to it (docs/vault-changes.md, section 3).
//
// Obsidian links look like `[[Note]]`, `[[Folder/Note]]`, `[[Note#Heading]]`,
// `[[Note|shown text]]` and `![[Note]]` (an embed). When a note moves or is
// renamed outside Obsidian, nothing updates those links. This is the rule for
// doing it ourselves, as a pure function from text to text, so every odd case
// can be tested.
//
// What is understood: wiki links, with or without a folder path, heading and
// block parts, alias and embed mark. What is NOT: ordinary Markdown links
// (`[text](Note.md)`), which are left as they are, and links inside code
// (a fenced block or `inline code`), which are never touched.

import Foundation

public enum WikiLinks {
    /// What a rewrite did.
    public struct Result: Equatable, Sendable {
        public var text: String
        /// How many links were changed.
        public var changed: Int
        /// Links that might mean the moved note but could also mean another note with the same name:
        /// left alone, never guessed.
        public var ambiguous: Int
    }

    /// Rewrites the links in `text` that point at the note `old` so they point at `new`.
    ///
    /// - `old`, `new`: vault-relative paths (`Wiki/Ideas/Plan.md`).
    /// - `notes`: every note in the vault BEFORE the move, `old` included. Obsidian resolves a link by its
    ///   name and path, so we need to know which other notes have the same name.
    public static func rewrite(_ text: String, moving old: String, to new: String, notes: [String]) -> Result {
        let before = Set(notes.map { $0.lowercased() })
        // The notes after the move: `old` is replaced by `new`.
        let after = Set(notes.filter { $0.lowercased() != old.lowercased() }.map { $0.lowercased() } + [new.lowercased()])

        var result = Result(text: "", changed: 0, ambiguous: 0)
        var lines = splitLines(text)
        var inFence: (marker: Character, length: Int)?
        for i in lines.indices {
            let body = lines[i].body
            // A fenced code block is skipped line by line.
            if let fence = fenceStart(body) {
                if let open = inFence {
                    if fence.marker == open.marker, fence.length >= open.length, fence.rest.allSatisfy({ $0 == " " || $0 == "\t" }) { inFence = nil }
                } else if !(fence.marker == "`" && fence.rest.contains("`")) {
                    inFence = (fence.marker, fence.length)
                }
                continue
            }
            if inFence != nil { continue }
            let (newBody, changed, ambiguous) = rewriteLine(body, old: old, new: new, before: before, after: after)
            lines[i].body = newBody
            result.changed += changed
            result.ambiguous += ambiguous
        }
        result.text = lines.map { $0.body + $0.end }.joined()
        return result
    }

    // MARK: - One line

    private static func rewriteLine(_ line: String, old: String, new: String, before: Set<String>, after: Set<String>) -> (String, Int, Int) {
        guard line.contains("[[") else { return (line, 0, 0) }
        let codeRanges = inlineCodeRanges(in: line)
        var out = ""
        var changed = 0, ambiguous = 0
        var index = line.startIndex
        // `[[` … `]]` with a target (no `|`, `#`, `^`, brackets), an optional `#heading` or `^block`, an optional `|alias`.
        let pattern = /(!?)\[\[([^\[\]|#^]*)((?:[#^][^\[\]|]*)?)((?:\|[^\[\]]*)?)\]\]/
        for match in line.matches(of: pattern) {
            let range = match.range
            out += line[index..<range.lowerBound]
            index = range.upperBound
            let original = String(line[range])
            if codeRanges.contains(where: { $0.overlaps(range) }) {
                out += original
                continue
            }
            let target = String(match.output.2)
            switch resolve(target: target, old: old, before: before) {
            case .other:
                out += original
            case .ambiguous:
                ambiguous += 1
                out += original
            case .old:
                let newTarget = newTarget(for: target, old: old, new: new, after: after)
                if newTarget == target {
                    out += original
                } else {
                    changed += 1
                    out += "\(match.output.1)[[\(newTarget)\(match.output.3)\(match.output.4)]]"
                }
            }
        }
        out += line[index...]
        return (out, changed, ambiguous)
    }

    // MARK: - Which note a link means

    enum Meaning { case old, other, ambiguous }

    /// Does the link target mean the note `old`? A target with a folder (`Wiki/Plan`) matches a note whose
    /// path ends with it; a plain name (`Plan`) matches a note with that file name. Case doesn't matter,
    /// and a trailing `.md` is allowed. If more than one note fits, the link is ambiguous.
    static func resolve(target: String, old: String, before: Set<String>) -> Meaning {
        let t = normalized(target)
        guard !t.isEmpty else { return .other }  // `[[#heading]]`: a link inside the same note
        let matches = before.filter { matches(path: $0, target: t) }
        guard matches.contains(old.lowercased()) else { return .other }
        // An exact full path always means exactly that note.
        if stripExtension(old.lowercased()) == t { return .old }
        return matches.count == 1 ? .old : .ambiguous
    }

    private static func matches(path: String, target: String) -> Bool {
        let p = stripExtension(path)
        return p == target || p.hasSuffix("/" + target)
    }

    /// The link text after the move. A full-path link gets the new full path; a plain name stays as it
    /// is when that still works, otherwise it becomes the new name (if unique) or the new full path.
    private static func newTarget(for target: String, old: String, new: String, after: Set<String>) -> String {
        let hadExtension = target.lowercased().hasSuffix(".md")
        let t = normalized(target)
        let oldPath = stripExtension(old.lowercased())
        let newPath = stripExtension(new)
        let newName = newPath.split(separator: "/").last.map(String.init) ?? newPath
        let oldName = oldPath.split(separator: "/").last.map(String.init) ?? oldPath

        let result: String
        if t.contains("/") {
            // A path: the new full path.
            result = newPath
        } else {
            // A plain name: still fine if it is the same name and no other note has it now.
            let sameNameNotes = after.filter { stripExtension($0).split(separator: "/").last.map(String.init) == newName.lowercased() }
            if newName.lowercased() == oldName, sameNameNotes.count == 1 {
                return target  // unchanged, whatever its capitals
            }
            result = sameNameNotes.count == 1 ? newName : newPath
        }
        return hadExtension ? result + ".md" : result
    }

    private static func normalized(_ target: String) -> String {
        stripExtension(target.trimmingCharacters(in: .whitespaces).lowercased())
    }

    private static func stripExtension(_ path: String) -> String {
        path.hasSuffix(".md") ? String(path.dropLast(3)) : path
    }

    // MARK: - Code

    /// A line that opens or closes a fenced code block: up to 3 spaces, then 3 or more backticks or tildes.
    private static func fenceStart(_ line: String) -> (marker: Character, length: Int, rest: Substring)? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        guard indent <= 3, let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let run = rest.prefix { $0 == marker }.count
        guard run >= 3 else { return nil }
        return (marker, run, rest.dropFirst(run))
    }

    /// The parts of a line between backticks (`inline code`, also ``double``). A run of backticks closes
    /// at the next run of the same length.
    static func inlineCodeRanges(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var i = line.startIndex
        while i < line.endIndex {
            guard line[i] == "`" else {
                i = line.index(after: i)
                continue
            }
            var open = i
            while open < line.endIndex, line[open] == "`" { open = line.index(after: open) }
            let length = line.distance(from: i, to: open)
            // Find the closing run of the same length.
            var search = open
            var closed: Range<String.Index>?
            while search < line.endIndex {
                if line[search] == "`" {
                    var end = search
                    while end < line.endIndex, line[end] == "`" { end = line.index(after: end) }
                    if line.distance(from: search, to: end) == length {
                        closed = i..<end
                        break
                    }
                    search = end
                } else {
                    search = line.index(after: search)
                }
            }
            if let closed {
                ranges.append(closed)
                i = closed.upperBound
            } else {
                i = open  // no closing run: the backticks are just text
            }
        }
        return ranges
    }

    // MARK: - Lines

    private struct Line {
        var body: String
        var end: String
    }

    /// Splits at `\n`, keeping `\r\n` together, so joining gives back exactly the original text.
    private static func splitLines(_ text: String) -> [Line] {
        var lines: [Line] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                if current.last == "\r" {
                    current.removeLast()
                    lines.append(Line(body: String(current), end: "\r\n"))
                } else {
                    lines.append(Line(body: String(current), end: "\n"))
                }
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { lines.append(Line(body: String(current), end: "")) }
        return lines
    }
}
