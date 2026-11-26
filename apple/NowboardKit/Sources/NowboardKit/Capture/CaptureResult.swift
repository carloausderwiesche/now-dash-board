// What the classifier made of a capture (spec 4): the JSON it answers with,
// checked and turned into a Swift value. Nothing here talks to the
// classifier; it only reads what came back.

import Foundation

/// What a capture is.
public enum CaptureKind: String, Sendable, CaseIterable {
    case task, note, question, unclear
}

/// Which list a suggested task goes to.
public enum CaptureStatus: String, Sendable, CaseIterable {
    case today, backlog
}

/// The classifier's answer, checked (spec 4.1 and 4.2).
public struct CaptureResult: Equatable, Sendable {
    public var kind: CaptureKind
    /// One line (spec 4.2).
    public var title: String
    public var body: String?
    /// Always one of the board's category ids (spec 4.2).
    public var area: String
    /// Missing means "the reader decides"; the task format says `backlog`.
    public var status: CaptureStatus?
    /// Model-chosen, so run it through `VaultPath.folder` before using it (spec 5).
    public var folder: String?
    public var confidence: Double
    public var followUp: String?

    /// Public so other classifiers (and test fakes) can make a result; `decode` is how the CLI's answer becomes one.
    public init(
        kind: CaptureKind, title: String, body: String? = nil, area: String, status: CaptureStatus? = nil, folder: String? = nil,
        confidence: Double, followUp: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.area = area
        self.status = status
        self.folder = folder
        self.confidence = confidence
        self.followUp = followUp
    }

    /// Below this the classifier isn't sure, so we ask (spec 4.3).
    ///
    /// A starting point, not a tuned value: in spike runs on 30 made-up
    /// inputs, wrong notes scored 0.50 to 0.55 and correct notes at least
    /// 0.60 (0.70 with `--safe-mode`); see
    /// docs/adr/0015-classify-captures-with-claude-cli.md. Tune it on real
    /// captures.
    public static let confidenceThreshold = 0.58

    /// The question asked when the classifier gave none.
    public static let defaultQuestion = "Is this a task, a note or a question?"

    /// True when the person must be asked: kind `unclear`, or not confident enough.
    public var needsQuestion: Bool {
        kind == .unclear || confidence < Self.confidenceThreshold
    }

    /// The kind to act on: `unclear` whenever we have to ask.
    public var effectiveKind: CaptureKind {
        needsQuestion ? .unclear : kind
    }

    /// What to ask when `needsQuestion` is true.
    public var question: String {
        followUp ?? Self.defaultQuestion
    }

    // MARK: - Reading

    /// Reads the classifier's JSON. `categoryIds` are the board's categories,
    /// in order; an `area` that isn't one of them becomes the first.
    public static func decode(_ data: Data, categoryIds: [String]) throws(CaptureError) -> CaptureResult {
        // What the JSON looks like. Everything is optional here so that we can
        // say *which* field is missing, instead of a vague decoding error.
        // Swift note: a type that conforms to `Decodable` can be filled from
        // JSON by `JSONDecoder`. A field with the wrong type (text where a
        // number should be) makes it throw, which is what we want (spec 4.2).
        struct Raw: Decodable {
            var kind: String?
            var title: String?
            var body: String?
            var area: String?
            var status: String?
            var folder: String?
            var confidence: Double?
            var follow_up: String?
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw .invalidResult("not the expected JSON object (\(error.localizedDescription))")
        }

        guard let kindText = raw.kind else { throw .invalidResult("kind is missing") }
        guard let kind = CaptureKind(rawValue: kindText) else {
            throw .invalidResult("unknown kind “\(kindText)”")
        }
        guard let title = raw.title?.asOneLine, !title.isEmpty else {
            throw .invalidResult("title is missing")
        }
        guard let confidence = raw.confidence else { throw .invalidResult("confidence is missing") }
        guard (0...1).contains(confidence) else {
            throw .invalidResult("confidence \(confidence) is not between 0 and 1")
        }
        var status: CaptureStatus? = nil
        if let statusText = raw.status?.trimmedOrNil {
            guard let known = CaptureStatus(rawValue: statusText) else {
                throw .invalidResult("unknown status “\(statusText)”")
            }
            status = known
        }
        // Spec 4.2: not a category → the first one; no categories at all → `personal`.
        let area = raw.area?.trimmedOrNil.flatMap { categoryIds.contains($0) ? $0 : nil }
            ?? categoryIds.first ?? "personal"

        return CaptureResult(
            kind: kind, title: title, body: raw.body?.trimmedOrNil, area: area, status: status,
            folder: raw.folder?.trimmedOrNil, confidence: confidence, followUp: raw.follow_up?.trimmedOrNil)
    }

    /// Same, for JSON as text.
    public static func decode(_ json: String, categoryIds: [String]) throws(CaptureError) -> CaptureResult {
        try decode(Data(json.utf8), categoryIds: categoryIds)
    }
}

extension String {
    /// Trimmed, or nil if that leaves nothing ("missing", spec 4.2).
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
