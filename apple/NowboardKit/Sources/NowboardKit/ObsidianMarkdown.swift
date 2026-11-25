// Notes as Obsidian writes them, turned into plain Markdown for display.
// Obsidian adds syntax that Markdown renderers don't know; the app shows the
// two that matter in task notes as links into Obsidian. The file itself is
// never changed: this is only what the card panel shows.

import Foundation

/// The Obsidian syntax that becomes a link.
public enum ObsidianLink: Equatable, Sendable {
    /// `[[Note]]`: another note, by name (without a heading).
    case note(String)
    /// `#tag`, without the `#`.
    case tag(String)
}

/// `[[Note|alias]]`, `![[embed]]` and `#tag` become Markdown links to wherever
/// `link` says. Without a link a wikilink shows as its text and a tag stays as
/// it is. Code spans and fenced code blocks are left alone, as in Obsidian.
public func obsidianToMarkdown(_ text: String, link: (ObsidianLink) -> URL?) -> String {
    var fenced = false
    return text.components(separatedBy: "\n").map { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            fenced.toggle()
            return line
        }
        if fenced { return line }
        return rewrite(line, codeSpan, match: { $0 }) { gap in
            rewrite(gap, syntax, match: { convert($0, link: link) }) { $0 }
        }
    }.joined(separator: "\n")
}

/// A wikilink or embed (group 1: what's inside the brackets), or a tag
/// (group 2): `#` after a space or at the start, not only digits, as Obsidian has it.
private let syntax = try! NSRegularExpression(
    pattern: #"!?\[\[([^\[\]]+)\]\]|(?<!\S)#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#)
private let codeSpan = try! NSRegularExpression(pattern: "(`+).+?\\1")

private func convert(_ match: String, link: (ObsidianLink) -> URL?) -> String {
    if match.hasPrefix("#") {
        let tag = String(match.dropFirst())
        return link(.tag(tag)).map { "[\(match)](<\($0.absoluteString)>)" } ?? match
    }
    let inner = match.drop { $0 == "!" }.dropFirst(2).dropLast(2)
    let (target, alias) = split(inner, at: "|")
    let (name, heading) = split(target, at: "#")
    let label = escape(alias ?? [name, heading ?? ""].filter { !$0.isEmpty }.joined(separator: " > "))
    guard !name.isEmpty, let url = link(.note(name)) else { return label }
    return "[\(label)](<\(url.absoluteString)>)"
}

private func split(_ s: some StringProtocol, at separator: Character) -> (String, String?) {
    guard let i = s.firstIndex(of: separator) else { return (s.trimmingCharacters(in: .whitespaces), nil) }
    return (s[..<i].trimmingCharacters(in: .whitespaces), s[s.index(after: i)...].trimmingCharacters(in: .whitespaces))
}

private func escape(_ label: String) -> String {
    label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
}

/// `text` with each match of `regex` passed through `match`, and the text
/// between matches through `gap`.
private func rewrite(_ text: String, _ regex: NSRegularExpression,
                     match: (String) -> String, gap: (String) -> String) -> String {
    let ns = text as NSString
    var out = ""
    var last = 0
    for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out += gap(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
        out += match(ns.substring(with: m.range))
        last = NSMaxRange(m.range)
    }
    return out + gap(ns.substring(from: last))
}
