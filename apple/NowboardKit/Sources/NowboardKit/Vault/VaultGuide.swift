// `_vault-guide.md`: a short description of how the vault is organised, which
// the classifier reads when it files a note (docs/vault-changes.md, section 1).
//
// The file has two parts. The person's own text, which Nowboard never changes,
// and one section between two marker lines that the AI keeps up to date. Every
// function here changes only what is between the markers.

import Foundation

public enum VaultGuide {
    public static let fileName = "_vault-guide.md"
    public static let startMarker = "<!-- nowboard:guide-start -->"
    public static let endMarker = "<!-- nowboard:guide-end -->"
    /// The most characters the AI's part may have.
    public static let maxAICharacters = 2000

    /// The text of a new guide: a place for the person's own words, then the AI's section.
    static let newFilePrefix = """
        # Vault guide

        Write your own notes about how this vault is organised here. Nowboard never changes anything outside the marked section below.


        """

    // MARK: - Reading

    /// The AI's part of a guide, without the markers (and without its fingerprint line), or nil if there is none.
    public static func aiSection(of text: String) -> String? {
        guard let range = blockRange(in: text) else { return nil }
        let inner = String(text[range.inner])
        return inner.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(digestPrefix) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The fingerprint of the folder tree the AI's part was written for, if the section has one.
    public static func treeDigest(in text: String) -> String? {
        guard let range = blockRange(in: text) else { return nil }
        for line in text[range.inner].split(separator: "\n") where line.hasPrefix(digestPrefix) {
            return line.dropFirst(digestPrefix.count).dropLast(" -->".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Everything outside the AI's section: the person's part.
    public static func humanText(of text: String) -> String {
        guard let range = blockRange(in: text) else { return text }
        return String(text[..<range.outer.lowerBound]) + String(text[range.outer.upperBound...])
    }

    // MARK: - Writing

    /// The guide with the AI's section set to `aiText` for the folder tree with fingerprint `digest`.
    /// - No file yet (`existing` nil): a new guide.
    /// - A file without our section: the section is added at the end; nothing else changes.
    /// - A file with our section: only what is between the markers is replaced; everything else stays, byte for byte.
    /// - A start marker without an end marker (a half section): nil. The text after it may be the
    ///   person's, so nothing is written until they fix the file.
    ///
    /// The AI's text is cut to `maxAICharacters` and can't contain a marker or a comment of its own.
    public static func updating(_ existing: String?, aiText: String, digest: String) -> String? {
        let block = makeBlock(aiText: aiText, digest: digest)
        guard let existing else { return newFilePrefix + block }
        switch scan(existing) {
        case .block(let outer, _):
            return String(existing[..<outer.lowerBound]) + block + String(existing[outer.upperBound...])
        case .malformed:
            return nil  // not exactly one section: the text around the markers may be the person's
        case .none:
            break
        }
        // No section yet: add it after what's there, with a blank line before.
        var result = existing
        if let last = result.unicodeScalars.last, last != "\n" { result += "\n" }
        // A blank line before the section, unless there is one (counted in scalars: `\r\n` is one Character).
        if !result.isEmpty, !endsWithBlankLine(result) { result += "\n" }
        return result + block
    }

    /// Whether the text ends with an empty line (`\n\n` or `\r\n\r\n`).
    private static func endsWithBlankLine(_ text: String) -> Bool {
        var scalars = Array(text.unicodeScalars.suffix(4))
        // Ignore the `\r` of a Windows line break.
        scalars.removeAll { $0 == "\r" }
        return scalars.suffix(2).count == 2 && scalars.suffix(2).allSatisfy { $0 == "\n" }
    }

    // MARK: - The block

    private static let digestPrefix = "<!-- nowboard:tree="

    /// The markers with the AI's text between them, ending with a line break.
    static func makeBlock(aiText: String, digest: String) -> String {
        var text = aiText
        // The AI can't write a marker or open a comment: that could swallow the person's text later.
        // Removing one can make another appear (`<<!--!--` becomes `<!--`), so repeat until none is left.
        while text.contains("<!--") || text.contains("-->") {
            for forbidden in ["<!--", "-->"] { text = text.replacingOccurrences(of: forbidden, with: "") }
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxAICharacters {
            text = String(text.prefix(maxAICharacters))
            // Cut at the last line break so no line is cut in half.
            if let cut = text.lastIndex(of: "\n") { text = String(text[..<cut]) }
        }
        let safeDigest = digest.filter { $0.isHexDigit }
        return "\(startMarker)\n\(digestPrefix)\(safeDigest) -->\n\(text)\n\(endMarker)\n"
    }

    /// Where our section is: all of it (markers included, with the line break after the end marker),
    /// and the part between the markers. Nil if there is none, OR if the markers are not exactly one start
    /// followed by one end (see `scan`).
    private static func blockRange(in text: String) -> (outer: Range<String.Index>, inner: Range<String.Index>)? {
        guard case .block(let outer, let inner) = scan(text) else { return nil }
        return (outer, inner)
    }

    enum Scan {
        case none
        case block(outer: Range<String.Index>, inner: Range<String.Index>)
        /// Marker lines that don't make exactly one section (two starts, an end first, a start alone…).
        case malformed
    }

    /// Finds the marker lines: a line that is exactly a marker (trailing spaces allowed), outside fenced
    /// code blocks. Exactly one start followed by one end is a section; no markers at all is none;
    /// anything else is malformed, and nothing is written over it.
    static func scan(_ text: String) -> Scan {
        var starts: [Range<String.Index>] = []
        var ends: [Range<String.Index>] = []
        var fence: (marker: Character, length: Int)?
        var i = text.startIndex
        while i < text.endIndex {
            let lineEnd = text[i...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[i..<lineEnd]
            let trimmed = line.drop { $0 == " " }
            // Fenced code blocks (``` or ~~~): markers inside them are text, not markers.
            if line.count - trimmed.count <= 3, let m = trimmed.first, m == "`" || m == "~" {
                let run = trimmed.prefix { $0 == m }.count
                if run >= 3 {
                    if let open = fence {
                        if m == open.marker, run >= open.length, trimmed.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) { fence = nil }
                    } else if !(m == "`" && trimmed.dropFirst(run).contains("`")) {
                        fence = (m, run)
                    }
                    i = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                    continue
                }
            }
            if fence == nil {
                let content = line.trimmingCharacters(in: .whitespaces)
                if content == startMarker { starts.append(i..<lineEnd) }
                if content == endMarker { ends.append(i..<lineEnd) }
            }
            i = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        if starts.isEmpty && ends.isEmpty { return .none }
        guard starts.count == 1, ends.count == 1, starts[0].upperBound <= ends[0].lowerBound else { return .malformed }
        var outerEnd = ends[0].upperBound
        if outerEnd < text.endIndex { outerEnd = text.index(after: outerEnd) }  // the line break after the end marker
        return .block(outer: starts[0].lowerBound..<outerEnd, inner: starts[0].upperBound..<ends[0].lowerBound)
    }
}
