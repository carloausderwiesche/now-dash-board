// Asking the classifier: run the claude tool for one capture and give back a
// checked `CaptureResult`. The process itself is started by a `ProcessRunning`
// that the app provides (macOS only); everything else is here, so it can be
// tested with a fake runner and without the real tool.

import Foundation

/// Anything that can classify a capture. A protocol so the app can use a
/// fake, or a different backend (the Ollama fallback of ADR 0015), later.
///
/// Swift note: a `protocol` lists what a type must be able to do, like an
/// interface. `any Classifier` means "some type that does".
public protocol Classifier: Sendable {
    func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult
}

/// What a finished process left behind.
public struct ProcessOutput: Equatable, Sendable {
    public var stdout: Data
    public var stderr: Data
    public var exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum ProcessRunError: Error, Equatable {
    /// It was still running at the timeout and was stopped.
    case timedOut
    /// The program isn't there.
    case executableNotFound
    /// It couldn't be started for another reason (no permission…).
    case launchFailed(String)
    /// The caller gave up (the task was cancelled); the program was stopped.
    case cancelled
}

/// Starts a program and waits for it. The app implements it with
/// `Foundation.Process` (macOS only); tests use a fake.
public protocol ProcessRunning: Sendable {
    func run(
        executable: URL, arguments: [String], workingDirectory: URL, timeout: Duration
    ) async throws(ProcessRunError) -> ProcessOutput
}

/// Classifies captures with the claude command-line tool (ADR 0015).
public struct ClaudeCLIClassifier: Classifier {
    /// Finds the tool each time (a setting may have changed). Nil = not found.
    public let locateExecutable: @Sendable () async -> URL?
    public let runner: any ProcessRunning
    public let timeout: Duration
    /// Told what the tool reported about each successful call (cost, tokens). Optional.
    public let onDiagnostics: (@Sendable (ClassifierDiagnostics) -> Void)?

    public init(
        locateExecutable: @escaping @Sendable () async -> URL?, runner: any ProcessRunning,
        timeout: Duration = .seconds(60), onDiagnostics: (@Sendable (ClassifierDiagnostics) -> Void)? = nil
    ) {
        self.locateExecutable = locateExecutable
        self.runner = runner
        self.timeout = timeout
        self.onDiagnostics = onDiagnostics
    }

    public func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult {
        guard let executable = await locateExecutable() else { throw .cliNotFound }

        // The tool runs in a new, empty folder, so it can't see (or be
        // tempted by) any of our files. It's deleted afterwards, whatever happens.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-classify-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .unreadableOutput("couldn't make a temporary folder: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let output: ProcessOutput
        do {
            output = try await runner.run(
                executable: executable, arguments: ClaudeCLI.arguments(for: input), workingDirectory: folder, timeout: timeout)
        } catch {
            // Swift note: with typed throws, `error` here is a `ProcessRunError`.
            switch error {
            case .timedOut: throw .timedOut
            // (A tool that vanished between finding it and starting it is "not found" too.)
            case .executableNotFound: throw .cliNotFound
            case .launchFailed(let why): throw .cliReportedError(why)
            case .cancelled: throw .cancelled
            }
        }

        // Some failures come as JSON on stdout together with an exit code
        // (`is_error`). Its message is better than a bare exit code.
        if output.exitCode != 0 {
            if case .cliReportedError(let text)? = Self.failure(in: output.stdout, categoryIds: input.categoryIds) {
                throw .cliReportedError(text)
            }
            let stderr = String(decoding: output.stderr.prefix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw .nonZeroExit(code: output.exitCode, stderr: String(stderr.prefix(300)))
        }

        let parsed = try ClaudeCLI.parse(output.stdout, categoryIds: input.categoryIds)
        onDiagnostics?(parsed.diagnostics)
        return parsed.result
    }

    /// The error `parse` finds in some output, if it's one.
    private static func failure(in stdout: Data, categoryIds: [String]) -> ClassifierError? {
        do {
            _ = try ClaudeCLI.parse(stdout, categoryIds: categoryIds)
            return nil
        } catch {
            return error
        }
    }
}
