// The `--- … ---` block at the top of a task file: splitting it off, reading
// it as an ordered list of fields, and writing it back (spec sections 2 and 5.2).

import Foundation
import Yams

// MARK: - Splitting

/// Splits a file into its YAML (nil if it has no frontmatter) and its body.
///
/// This works on UTF-8 **bytes**, not on Swift `String`s, on purpose. Swift
/// treats `\r\n` as a single character, so searching a `String` for `"\n---"`
/// can miss a `---` that follows a Windows line break. Bytes have no such
/// surprises, and they keep the body exactly as it was (spec 2.1).
func splitFrontmatter(_ text: String) -> (yaml: String?, body: String) {
    var bytes = Array(text.utf8)
    // 1. Drop a byte-order mark (U+FEFF, which is EF BB BF in UTF-8).
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
        bytes.removeFirst(3)
    }
    let dashes: [UInt8] = Array("---".utf8)
    let lf = UInt8(ascii: "\n"), cr = UInt8(ascii: "\r")

    // 2. Frontmatter only if the file starts with `---` and a line break.
    var start: Int
    if bytes.starts(with: dashes + [lf]) {
        start = 4
    } else if bytes.starts(with: dashes + [cr, lf]) {
        start = 5
    } else {
        return (nil, string(bytes[...]))
    }

    // 3. It ends at the first following line that starts with `---`.
    var end: Int? = nil
    if bytes[start...].starts(with: dashes) {
        end = start  // empty frontmatter: `---` right away
    } else {
        var i = start
        while i < bytes.count {
            if bytes[i] == lf && bytes[(i + 1)...].starts(with: dashes) {
                end = i + 1
                break
            }
            i += 1
        }
    }
    // 5. No closing line: no frontmatter, the whole text is the body.
    guard let close = end else { return (nil, string(bytes[...])) }

    // 4. Skip one line break after the closing `---`; the rest is the body.
    var bodyStart = close + 3
    if bytes[bodyStart...].starts(with: [cr, lf]) {
        bodyStart += 2
    } else if bytes[bodyStart...].starts(with: [lf]) {
        bodyStart += 1
    }
    return (string(bytes[start..<close]), string(bytes[bodyStart...]))
}

/// Bytes back to text. The input came from a valid `String`, and we only cut
/// it next to ASCII characters, so this can't fail.
private func string(_ bytes: ArraySlice<UInt8>) -> String {
    String(decoding: bytes, as: UTF8.self)
}

// MARK: - Reading

/// Why a frontmatter can't be used. Saving refuses such a file (spec 5.1).
public enum FrontmatterError: Error, Equatable {
    case invalidYAML(String)
    case notAMapping
}

/// One field of the frontmatter. `Node` is Yams' name for "a piece of YAML":
/// a scalar (`work`, `1024`), a list or a map. We keep the parsed node itself,
/// so a field we don't know is written back with the same value and quoting.
struct Field: Equatable {
    var key: Node
    var value: Node
}

/// The frontmatter as an **ordered** list of fields. An array (not a
/// `Dictionary`) because order matters: fields other programs wrote must stay
/// where they were (spec 5.1).
struct Frontmatter: Equatable {
    var fields: [Field] = []

    /// Parses YAML text. Empty text, or `null`, gives no fields.
    static func parse(_ yaml: String) throws(FrontmatterError) -> Frontmatter {
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Frontmatter()
        }
        let node: Node?
        do {
            node = try Yams.compose(yaml: yaml)
        } catch {
            throw .invalidYAML(String(describing: error))
        }
        switch node {
        case nil:
            return Frontmatter()
        case .mapping(let mapping):
            // (Yams already refuses a key that appears twice, as YAML requires.)
            var result = Frontmatter()
            for (key, value) in mapping {
                result.fields.append(Field(key: key, value: value))
            }
            return result
        case .scalar(let s) where YAMLValue(s) == .null:
            return Frontmatter()
        default:
            throw .notAMapping
        }
    }

    private func index(of key: String) -> Int? {
        fields.firstIndex { $0.key.scalar?.string == key }
    }

    /// The value of a field, or nil if there's no such field.
    subscript(key: String) -> Node? {
        index(of: key).map { fields[$0].value }
    }

    /// Sets a field. An existing field keeps its position; a new one goes at the end.
    mutating func set(_ key: String, _ value: Node) {
        if let i = index(of: key) {
            fields[i].value = value
        } else {
            fields.append(Field(key: .scalar(stringScalar(key)), value: value))
        }
    }

    /// Removes a field. `Array.remove(at:)` closes the gap, so the other fields
    /// keep their order (the bug Rust had with a "swap remove": fixture 18).
    /// `@discardableResult` means callers may ignore the returned Bool.
    @discardableResult
    mutating func remove(_ key: String) -> Bool {
        guard let i = index(of: key) else { return false }
        fields.remove(at: i)
        return true
    }

    /// Writes the fields as YAML, one `key: value` per line (spec 5.2).
    func render() throws -> String {
        var out = ""
        for field in fields {
            // A missing value (`~`, `null` or nothing) is written as a bare `key:`.
            var value = field.value
            if case .scalar(let s) = value, YAMLValue(s) == .null {
                value = nullNode()
            }
            out += try serialized(.mapping(Node.Mapping([(field.key, value)])))
        }
        return out
    }
}

/// YAML text for one node. `allowUnicode` keeps `é` as `é` (instead of
/// `"\xE9"`), and `width: -1` stops long values from being wrapped onto
/// several lines.
private func serialized(_ node: Node) throws -> String {
    try Yams.serialize(node: node, width: -1, allowUnicode: true)
}

// MARK: - What a value means

/// What a scalar means, the way Rust's YAML library (and YAML 1.2) reads it.
///
/// We don't use Yams' own interpretation for this, because it follows the
/// older YAML 1.1 rules: there `yes` and `on` are booleans, and
/// `done: 2026-11-22` is a date. The spec wants `focus: yes` to stay off and
/// `done:` to stay text, so we look at the raw text and its quoting ourselves.
enum YAMLValue: Equatable {
    case null
    case bool(Bool)
    case number(Double, isInteger: Bool)
    case string(String)

    init(_ scalar: Node.Scalar) {
        let raw = scalar.string
        // Anything quoted (or a `|` / `>` block) is text, whatever it looks like.
        guard scalar.style == .plain || scalar.style == .any else {
            self = .string(raw)
            return
        }
        switch raw {
        case "", "~", "null", "Null", "NULL": self = .null
        case "true", "True", "TRUE": self = .bool(true)
        case "false", "False", "FALSE": self = .bool(false)
        default:
            if let n = YAMLValue.number(raw) {
                self = n
            } else {
                self = .string(raw)
            }
        }
    }

    /// YAML 1.2 numbers: `12`, `-3`, `0x1F`, `0o17`, `1024.5`, `1e3`, `.inf`, `.nan`.
    private static func number(_ raw: String) -> YAMLValue? {
        if raw.wholeMatch(of: /[-+]?[0-9]+/) != nil, let d = Double(raw) {
            return .number(d, isInteger: true)
        }
        if let m = raw.wholeMatch(of: /0x([0-9a-fA-F]+)/), let i = Int(m.1, radix: 16) {
            return .number(Double(i), isInteger: true)
        }
        if let m = raw.wholeMatch(of: /0o([0-7]+)/), let i = Int(m.1, radix: 8) {
            return .number(Double(i), isInteger: true)
        }
        if raw.wholeMatch(of: /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/) != nil, let d = Double(raw) {
            return .number(d, isInteger: false)
        }
        switch raw {
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .number(.infinity, isInteger: false)
        case "-.inf", "-.Inf", "-.INF": return .number(-.infinity, isInteger: false)
        case ".nan", ".NaN", ".NAN": return .number(.nan, isInteger: false)
        default: return nil
        }
    }
}

/// Reads a field "as text" (spec 2.2): missing, null or blank → nil; text as
/// it is; a boolean or number in its usual form; a list or map as YAML text.
func fieldText(_ node: Node?) -> String? {
    switch node {
    case nil, .alias:
        return nil
    case .scalar(let s):
        switch YAMLValue(s) {
        case .null: return nil
        case .string(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : t
        case .bool(let b): return String(b)
        case .number(let d, let isInteger): return isInteger ? String(Int(d)) : numberText(d)
        }
    case .some(let other):
        // e.g. an unquoted `project: [[Wiki/X]]`, which YAML reads as a nested
        // list. The spec leaves this undefined; show it as YAML text.
        return (try? serialized(other))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `1024` for whole numbers, `1024.5` otherwise (spec 5.2).
func numberText(_ d: Double) -> String {
    if d == d.rounded(), abs(d) < 1e15 {
        return String(Int64(d))
    }
    // Swift's `description` gives the shortest text that reads back as the
    // same number (`0.1`, not `0.1000000000000000055…`), like Rust does.
    return d.description
}

// MARK: - Writing values

/// A YAML node for a number we write (`order`).
func numberNode(_ d: Double) -> Node {
    .scalar(Node.Scalar(numberText(d), .implicit, .plain))
}

/// A YAML node for a string we write. Plain (no quotes) when YAML reads the
/// plain text back as this exact string; otherwise single-quoted. So the
/// category id `2026` or the title `true` can't come back as a number or a
/// boolean. (Yams would happily write them without quotes.)
func stringNode(_ s: String) -> Node {
    .scalar(stringScalar(s))
}

private func stringScalar(_ s: String) -> Node.Scalar {
    let plain = Node.Scalar(s, .implicit, .plain)
    let readsBack = YAMLValue(plain) == .string(s)
    let simple = !s.isEmpty && s == s.trimmingCharacters(in: .whitespaces)
        && !s.unicodeScalars.contains { $0.properties.generalCategory == .control }
    // For anything else, libyaml itself falls back to quotes when plain isn't
    // allowed (`[[X]]`, `a: b`, `# x`), so `.plain` is a wish, not a promise.
    if readsBack && simple {
        return plain
    }
    return Node.Scalar(s, .implicit, .singleQuoted)
}

/// The null node, written as a bare `key:`. A function, not a constant:
/// Swift 6 refuses global constants of types that aren't marked safe to share
/// between threads (`Sendable`), and Yams' `Node` isn't.
func nullNode() -> Node {
    .scalar(Node.Scalar("", .implicit, .plain))
}
