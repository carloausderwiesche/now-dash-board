// Blocking sites by editing the hosts file: the pure text rules (docs/adr/0019).
//
// The hosts file (`/etc/hosts`) tells the Mac which address a name has. A line
// `127.0.0.1 youtube.com` sends that name to the Mac itself, where nothing
// answers: the site doesn't load. During a focus session the app adds such
// lines between two marker lines, and takes exactly those lines out again.
//
// Everything here is a function from text to text. It never touches a file,
// so every odd case (no final line break, Windows line breaks, half a block)
// is tested without risk. The part that writes the real file is separate
// (`HostsBlockController`).
//
// This code runs as root inside the helper, so it is strict: the names it
// writes must be plain host names, and no other line of the file is changed.

import Foundation

public enum HostsBlock {
    /// The two marker lines around our block.
    public static let startMarker = "# >>> nowboard focus block"
    public static let endMarker = "# <<< nowboard focus block"

    /// Most names one block may hold (a wrong or hostile caller can't make the file huge).
    public static let maxDomains = 500

    // MARK: - Names

    /// Whether `name` is a plain host name we are willing to write into the hosts file:
    /// letters, digits and hyphens in dot-separated parts, lower case, at least two parts,
    /// the last part not all digits (so an IP address is not a name). No spaces, no line breaks, no `#`.
    ///
    /// Swift note: `wholeMatch` against a regular expression must match the whole text.
    /// ASCII only: an international name must be given in its `xn--` form.
    public static func isValidDomain(_ name: String) -> Bool {
        guard name.utf8.count <= 253 else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for part in parts {
            // 1 to 63 letters, digits and hyphens, not starting or ending with a hyphen.
            guard part.wholeMatch(of: /[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?/) != nil else { return false }
        }
        // The last part (the top-level domain) can't be only digits: `127.0.0.1` is an address, not a name.
        guard let last = parts.last, last.contains(where: { $0 >= "a" && $0 <= "z" }) else { return false }
        return true
    }

    /// The valid names of `names`, lower-cased (a trailing dot removed), without duplicates, sorted,
    /// at most `maxDomains`. Anything invalid is dropped, never repaired.
    public static func sanitize(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            var name = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if name.hasSuffix(".") { name.removeLast() }
            guard isValidDomain(name), seen.insert(name).inserted else { continue }
            result.append(name)
        }
        return Array(result.sorted().prefix(maxDomains))
    }

    // MARK: - Lines

    /// The lines for one name: the IPv4 loopback and the IPv6 loopback.
    static func entries(for name: String) -> [String] {
        ["127.0.0.1 \(name)", "::1 \(name)"]
    }

    /// Whether a line is one of ours: `127.0.0.1 name` or `::1 name` with a valid name, nothing else.
    static func isOurEntry(_ line: String) -> Bool {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, parts[0] == "127.0.0.1" || parts[0] == "::1" else { return false }
        return isValidDomain(String(parts[1]))
    }

    // MARK: - Text

    /// The file's text with our block added at the end (any block of ours that was there is replaced).
    /// Names are checked again here; if none is valid the text is returned without a block.
    /// Line breaks follow the file (`\r\n` if it uses them). Idempotent: doing it twice gives the same text.
    public static func inserting(domains: [String], into text: String) -> String {
        let clean = sanitize(domains)
        var result = removing(from: text)
        guard !clean.isEmpty else { return result }
        let eol = lineEnding(of: text)
        // (`hasSuffix("\n")` would miss a `\r\n` ending: Swift sees those two as one character.)
        if let last = result.unicodeScalars.last, last != "\n" { result += eol }
        var block = [startMarker]
        for name in clean { block += entries(for: name) }
        block.append(endMarker)
        result += block.joined(separator: eol) + eol
        return result
    }

    /// The file's text without our block. Only our own lines are touched:
    /// - a complete block (start marker, end marker): the markers and the lines of ours between
    ///   them go; any other line between them (someone added it by hand) stays;
    /// - a start marker with no end marker (the file was cut): the marker goes, and the lines of
    ///   ours right below it; everything from the first other line on stays;
    /// - an end marker with no start marker: that line goes;
    /// - blocks that appear several times: all go.
    /// Every other line stays exactly as it was, including its line break.
    public static func removing(from text: String) -> String {
        var lines = splitLines(text)
        var out: [Line] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let content = line.body.trimmingCharacters(in: .whitespaces)
            if content == startMarker {
                // Find the end marker of this block, if there is one.
                if let end = (i + 1..<lines.count).first(where: { lines[$0].body.trimmingCharacters(in: .whitespaces) == endMarker }) {
                    // Keep what is between the markers unless it's one of our entries.
                    out += lines[(i + 1)..<end].filter { !isOurEntry($0.body.trimmingCharacters(in: .whitespaces)) }
                    i = end + 1
                } else {
                    // No end: drop the marker and our own lines right under it, keep the rest.
                    i += 1
                    while i < lines.count, isOurEntry(lines[i].body.trimmingCharacters(in: .whitespaces)) { i += 1 }
                }
                continue
            }
            if content == endMarker {  // an end without a start: just that line
                i += 1
                continue
            }
            out.append(line)
            i += 1
        }
        lines = out
        return lines.map { $0.body + $0.end }.joined()
    }

    /// Whether the text holds any trace of our block (a marker line).
    public static func hasBlock(in text: String) -> Bool {
        splitLines(text).contains {
            let c = $0.body.trimmingCharacters(in: .whitespaces)
            return c == startMarker || c == endMarker
        }
    }

    // MARK: - Lines with their endings

    struct Line {
        var body: String
        var end: String
    }

    /// Splits at `\n`, keeping `\r\n` together, so joining gives back exactly the original text.
    /// (Swift sees `\r\n` as one character, so this walks the unicode scalars, like `DailyNote` does.)
    static func splitLines(_ text: String) -> [Line] {
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

    /// `\r\n` if the first line break in the text is one, otherwise `\n`.
    static func lineEnding(of text: String) -> String {
        splitLines(text).first { !$0.end.isEmpty }?.end ?? "\n"
    }
}
