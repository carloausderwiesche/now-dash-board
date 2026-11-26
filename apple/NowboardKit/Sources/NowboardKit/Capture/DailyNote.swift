// Adding a line to a daily note's "## Captured" section (spec 6).
//
// This is a pure function: text in, text out. It never touches the disk, so
// every odd case (no final line break, CRLF, a heading inside a code block)
// can be tested without files. Whoever calls it reads the note, calls this,
// and writes the result back.

import Foundation

public enum DailyNote {
    public static let heading = "## Captured"

    /// `text` with `line` added under the Captured heading (spec 6). Nothing
    /// else in `text` changes, except that a missing final line break is added.
    ///
    /// `line` is added exactly as given, so pass a list item (`- 13:05 text`).
    /// A line that starts with `#` would be a heading and end the section.
    public static func appendingCaptured(_ line: String, to text: String) -> String {
        let item = line.asOneLine
        guard !item.isEmpty else { return text }

        var lines = splitLines(text)
        // Use the note's own kind of line break for everything we add.
        let eol = lines.first { !$0.end.isEmpty }?.end ?? "\n"

        // Which lines may be headings at all (not frontmatter, not in code blocks).
        let real = headingCandidates(in: lines)
        let found = lines.indices.first { real[$0] && lines[$0].body.trimmingCharacters(in: .whitespaces) == heading && lines[$0].body.hasPrefix(heading) }

        if let h = found {
            // The section ends at the next level 1 or 2 heading (or the end).
            var at = (h + 1..<lines.count).first { real[$0] && isMajorHeading(lines[$0].body) } ?? lines.count
            // Go back over blank lines: the new line sits right under the
            // last real line, and the blank lines stay between sections.
            while at - 1 > h && lines[at - 1].body.trimmingCharacters(in: .whitespaces).isEmpty {
                at -= 1
            }
            if lines[at - 1].end.isEmpty { lines[at - 1].end = eol }  // the last line had no break
            lines.insert(Line(body: item, end: eol), at: at)
        } else {
            if var last = lines.last {
                if last.end.isEmpty {
                    last.end = eol
                    lines[lines.count - 1] = last
                }
                // A blank line before the heading, unless there already is one.
                if !last.body.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(Line(body: "", end: eol))
                }
            }
            lines.append(Line(body: heading, end: eol))
            lines.append(Line(body: item, end: eol))
        }
        return lines.map { $0.body + $0.end }.joined()
    }

    /// `text` without the line `line`, or nil if no line is exactly that.
    /// For Undo: it takes out the one line we added, and only if it's still
    /// there as we wrote it. If the person edited it, nothing is removed.
    /// If the same line is there more than once, the last one goes. The
    /// heading stays, and so does everything else.
    public static func removingLine(_ line: String, from text: String) -> String? {
        var lines = splitLines(text)
        guard let index = lines.lastIndex(where: { $0.body == line }) else { return nil }
        lines.remove(at: index)
        return lines.map { $0.body + $0.end }.joined()
    }

    // MARK: - Lines

    /// One line of the text and the line break that ended it (empty for a last
    /// line with no break). Keeping the break next to the line means joining
    /// everything again gives back exactly the original text.
    private struct Line {
        var body: String
        var end: String
    }

    /// Splits at `\n`, keeping `\r\n` together.
    ///
    /// Swift note: we walk the *unicode scalars* (the code points) and not the
    /// `Character`s. Swift sees `\r\n` as ONE Character, so a search for `\n`
    /// over Characters would never find it in a Windows file.
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
        if !current.isEmpty {
            lines.append(Line(body: String(current), end: ""))
        }
        return lines
    }

    /// Which lines are outside frontmatter and code blocks, and so can be headings.
    private static func headingCandidates(in lines: [Line]) -> [Bool] {
        var result = [Bool](repeating: true, count: lines.count)
        var start = 0
        // Frontmatter: a first line `---`, up to the next line that is exactly `---`.
        if let first = lines.first, first.body.trimmingCharacters(in: .whitespaces) == "---",
            let close = (1..<lines.count).first(where: { lines[$0].body.trimmingCharacters(in: .whitespaces) == "---" }) {
            for i in 0...close { result[i] = false }
            start = close + 1
        }
        // Fenced code blocks, the CommonMark way: up to 3 spaces, then 3 or
        // more backticks (or tildes). A backtick fence's first line can't have
        // another backtick after it (that's inline code like ```x```). It
        // closes at a line of only the same character, at least as long.
        var open: (marker: Character, length: Int)? = nil
        for i in start..<lines.count {
            let body = lines[i].body
            let indent = body.prefix { $0 == " " }.count
            let rest = body.dropFirst(indent)
            let marker = rest.first
            let run = rest.prefix { $0 == marker }.count
            let isFenceLine = indent <= 3 && (marker == "`" || marker == "~") && run >= 3
            if let current = open {
                result[i] = false
                let after = rest.dropFirst(run)
                if isFenceLine, marker == current.marker, run >= current.length,
                    after.allSatisfy({ $0 == " " || $0 == "\t" }) {
                    open = nil
                }
            } else if isFenceLine, let marker {
                let info = rest.dropFirst(run)
                if marker == "`" && info.contains("`") { continue }  // inline code, not a fence
                result[i] = false
                open = (marker, run)
            }
        }
        return result
    }

    /// `# …` or `## …` (also a bare `#` or `##`): ends the Captured section.
    private static func isMajorHeading(_ body: String) -> Bool {
        for prefix in ["#", "##"] where body == prefix || body.hasPrefix(prefix + " ") || body.hasPrefix(prefix + "\t") {
            return true
        }
        return false
    }
}
