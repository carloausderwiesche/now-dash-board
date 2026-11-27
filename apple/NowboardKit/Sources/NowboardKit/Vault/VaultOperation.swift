// What the AI may ask for when tidying the vault (docs/vault-changes.md,
// section 2): four small operations, and nothing that deletes. Reading the
// AI's JSON into operations is here; deciding whether one is allowed is
// `VaultChanges.validate`.

import Foundation

public struct VaultOperation: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Moves a note to another folder (and may rename it). Links to it are updated.
        case move
        /// Gives a note a new file name in the same folder. Links to it are updated.
        case rename
        /// Adds text at the end of a note.
        case append
        /// Changes the text of a note's first `# ` heading.
        case retitle
    }

    public var kind: Kind
    /// The note, relative to the vault (`Wiki/Ideas/Plan.md`).
    public var path: String
    /// `move`: the new path.
    public var to: String?
    /// `rename`: the new name (without `.md`).
    public var name: String?
    /// `append`: the text to add.
    public var text: String?
    /// `retitle`: the new heading.
    public var title: String?
    /// Why, in the AI's words, for the person to read.
    public var reason: String?

    public init(
        kind: Kind, path: String, to: String? = nil, name: String? = nil, text: String? = nil, title: String? = nil, reason: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.to = to
        self.name = name
        self.text = text
        self.title = title
        self.reason = reason
    }

    /// A line for the person: what this does.
    public var summary: String {
        switch kind {
        case .move: "Move \(path) to \(to ?? "?")"
        case .rename: "Rename \(path) to \(name ?? "?")"
        case .append: "Add a line to \(path)"
        case .retitle: "Change the title of \(path) to “\(title ?? "?")”"
        }
    }

    // MARK: - From the AI's answer

    /// Most operations read from one answer.
    public static let maxOperations = 20

    /// Reads `{"operations": [...]}`. An operation with an unknown kind or missing parts is dropped and
    /// counted, never repaired. At most `maxOperations` are kept.
    public static func decodeList(_ data: Data) throws(CaptureError) -> (operations: [VaultOperation], dropped: Int) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = object["operations"] as? [Any] else {
            throw .invalidResult("the answer has no list of operations")
        }
        var operations: [VaultOperation] = []
        var dropped = 0
        for item in list {
            guard operations.count < maxOperations else {
                dropped += 1
                continue
            }
            guard let fields = item as? [String: Any], let kindText = fields["op"] as? String, let kind = Kind(rawValue: kindText),
                let path = (fields["path"] as? String)?.trimmedOrNil
            else {
                dropped += 1
                continue
            }
            func text(_ key: String) -> String? { (fields[key] as? String)?.trimmedOrNil }
            let operation = VaultOperation(
                kind: kind, path: path, to: text("to"), name: text("name"), text: (fields["text"] as? String), title: text("title"),
                reason: text("reason"))
            // Each kind needs its own part.
            let complete: Bool =
                switch kind {
                case .move: operation.to != nil
                case .rename: operation.name != nil
                case .append: operation.text?.trimmedOrNil != nil
                case .retitle: operation.title != nil
                }
            if complete { operations.append(operation) } else { dropped += 1 }
        }
        return (operations, dropped)
    }

    /// The schema of the AI's answer (the `--json-schema`).
    public static var schema: JSONValue {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["operations"],
            "properties": [
                "operations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["op", "path"],
                        "properties": [
                            "op": ["type": "string", "enum": .array(Kind.allCases.map { .string($0.rawValue) })],
                            "path": ["type": "string", "description": "The note, relative to the vault, ending in .md"],
                            "to": ["type": "string", "description": "move: the new path, ending in .md"],
                            "name": ["type": "string", "description": "rename: the new file name without .md"],
                            "text": ["type": "string", "description": "append: the text to add at the end"],
                            "title": ["type": "string", "description": "retitle: the new first heading"],
                            "reason": ["type": "string", "description": "one short sentence"],
                        ],
                    ],
                ]
            ],
        ]
    }
}
