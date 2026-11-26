// A JSON value as a Swift type, so the result schema can be a constant that
// is safe to share between threads (spec 7).
//
// Swift note: Foundation's own JSON values are `[String: Any]`, and `Any`
// isn't `Sendable` (not marked safe to hand to another thread), which Swift 6
// refuses for global constants. This small enum is the plain alternative.
// The `ExpressibleBy…Literal` parts let us write a schema almost like JSON:
// `["type": "string", "enum": ["a", "b"]]`.

import Foundation

public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension JSONValue {
    /// The value as Foundation's untyped JSON, for `JSONSerialization`.
    var foundationValue: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b
        case .array(let a): a.map(\.foundationValue)
        case .object(let o): o.mapValues(\.foundationValue)
        }
    }

    /// The value as JSON text, keys sorted so the output is always the same.
    public func jsonString() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: foundationValue, options: [.sortedKeys, .fragmentsAllowed]) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
