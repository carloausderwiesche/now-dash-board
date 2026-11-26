// Talking to the `claude` command-line tool, the pure part (ADR 0015): what
// to type, and how to read what comes back. Nothing here starts a process;
// `ClaudeCLIClassifier` (below) does that through a `ProcessRunning`, so all
// of it can be tested with a fake.
//
// Flags: https://code.claude.com/docs/en/headless and
// https://code.claude.com/docs/en/cli-reference. Only `--tools ""` and
// `--safe-mode` were confirmed by actually running them (the spike script);
// the rest is from those pages.

import Foundation

/// Everything one classification needs.
public struct CaptureInput: Sendable, Equatable {
    public var text: String
    public var today: Date
    public var timeZone: TimeZone
    public var categoryIds: [String]
    /// The folder tree from `VaultMap.render`, or empty.
    public var vaultMap: String
    /// The contents of `_vault-guide.md`, if any.
    public var vaultGuide: String?

    public init(
        text: String, today: Date = Date(), timeZone: TimeZone = .current, categoryIds: [String],
        vaultMap: String = "", vaultGuide: String? = nil
    ) {
        self.text = text
        self.today = today
        self.timeZone = timeZone
        self.categoryIds = categoryIds
        self.vaultMap = vaultMap
        self.vaultGuide = vaultGuide
    }

    /// The prompt for the classifier (spec 7).
    public var prompt: String {
        CapturePrompt.build(
            text: text, today: today, timeZone: timeZone, categoryIds: categoryIds, vaultMap: vaultMap, vaultGuide: vaultGuide)
    }
}

/// Why a classification failed. Every case has a sentence a person can read.
public enum ClassifierError: Error, Equatable, LocalizedError {
    case cliNotFound
    /// The tool ran and said it failed (`is_error`). The text is what it said.
    case cliReportedError(String)
    case timedOut
    /// The task was cancelled while the tool ran.
    case cancelled
    /// The tool quit with an error code. `stderr` is cut short.
    case nonZeroExit(code: Int32, stderr: String)
    /// The tool answered, but not in the shape we asked for (text, cut-off JSON).
    case unreadableOutput(String)
    case noStructuredOutput
    /// The answer was JSON but failed our checks (`CaptureResult.decode`).
    case invalidResult(String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "The claude command-line tool wasn't found. Install it, or set its path in the settings."
        case .cliReportedError(let text): "Claude reported an error: \(text)"
        case .timedOut: "Claude took too long to answer."
        case .cancelled: "The classification was cancelled."
        case .nonZeroExit(let code, let stderr):
            stderr.isEmpty ? "Claude stopped with error code \(code)." : "Claude stopped with error code \(code): \(stderr)"
        case .unreadableOutput(let preview): "Claude's answer couldn't be read: \(preview)"
        case .noStructuredOutput: "Claude's answer had no result in it."
        case .invalidResult(let why): "Claude's answer can't be used: \(why)"
        }
    }
}

/// What the tool reports about the call besides the answer. All optional:
/// it's for looking at, never needed.
public struct ClassifierDiagnostics: Equatable, Sendable {
    public var totalCostUSD: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var durationMs: Int?
}

public enum ClaudeCLI {
    /// The arguments, in this order (ADR 0015):
    ///
    ///     -p <prompt> --output-format json --json-schema <schema>
    ///     --no-session-persistence --tools "" --safe-mode
    ///
    /// No `--bare` (it skips the subscription login) and no `--model` (the
    /// tool's default model). The schema is compact JSON on one line.
    ///
    /// Swift note: this is an array of separate strings, not one line of
    /// text. A process gets its arguments one by one, so no quoting is
    /// needed and a quote typed in a capture can't change the command.
    public static func arguments(for input: CaptureInput) -> [String] {
        [
            "-p", input.prompt,
            "--output-format", "json",
            "--json-schema", CaptureSchema.make(categoryIds: input.categoryIds).jsonString(),
            "--no-session-persistence",
            "--tools", "",
            "--safe-mode",
        ]
    }

    /// A reading of the tool's output.
    public struct Parsed: Equatable, Sendable {
        public var result: CaptureResult
        public var diagnostics: ClassifierDiagnostics
    }

    /// Reads what the tool printed: one JSON object, or a list whose last
    /// `"type": "result"` entry counts. Errors say what was wrong.
    public static func parse(_ stdout: Data, categoryIds: [String]) throws(ClassifierError) -> Parsed {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: stdout)
        } catch {
            throw .unreadableOutput(preview(of: stdout))
        }
        let final: [String: Any]
        if let one = object as? [String: Any] {
            final = one
        } else if let list = object as? [Any],
            let last = list.last(where: { ($0 as? [String: Any])?["type"] as? String == "result" }) as? [String: Any]
        {
            final = last
        } else {
            throw .unreadableOutput(preview(of: stdout))
        }

        if final["is_error"] as? Bool == true {
            let text = (final["result"] as? String)?.trimmedOrNil ?? (final["subtype"] as? String) ?? "unknown error"
            throw .cliReportedError(text)
        }
        // `structured_output` is where `--json-schema` puts the answer.
        // (`result` holds the same thing as text, but only this field is a checked object.)
        guard let structured = final["structured_output"], !(structured is NSNull),
            JSONSerialization.isValidJSONObject(structured)
        else { throw .noStructuredOutput }
        let answer: Data
        do {
            answer = try JSONSerialization.data(withJSONObject: structured)
        } catch {
            throw .noStructuredOutput
        }
        let result: CaptureResult
        do {
            result = try CaptureResult.decode(answer, categoryIds: categoryIds)
        } catch {
            // `decode` only throws `CaptureError.invalidResult`; the message is what we want.
            throw .invalidResult(error.errorDescription ?? "unknown")
        }

        let usage = final["usage"] as? [String: Any]
        let diagnostics = ClassifierDiagnostics(
            totalCostUSD: (final["total_cost_usd"] as? NSNumber)?.doubleValue,
            inputTokens: (usage?["input_tokens"] as? NSNumber)?.intValue,
            outputTokens: (usage?["output_tokens"] as? NSNumber)?.intValue,
            durationMs: (final["duration_ms"] as? NSNumber)?.intValue)
        return Parsed(result: result, diagnostics: diagnostics)
    }

    /// The start of some output as text, for error messages.
    static func preview(of data: Data, limit: Int = 200) -> String {
        let text = String(decoding: data.prefix(limit * 4), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "(nothing)" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
