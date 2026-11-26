// The claude command-line side: the arguments, reading its output, the
// classifier with a fake process, and finding the program. No real `claude`
// is started here.

import Foundation
import Testing

@testable import NowboardKit

private let cliFixtures: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("fixtures/capture/cli-output")
}()

private let outputCases: [String] = {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: cliFixtures.path)) ?? []
    return files.filter { $0.hasSuffix(".expected.json") }.map { String($0.dropLast(".expected.json".count)) }.sorted()
}()

private let categories = ["personal", "work"]
private let day = Date(timeIntervalSince1970: 1_795_000_000)
private let utc = TimeZone(identifier: "UTC")!

private func input(_ text: String = "call the dentist") -> CaptureInput {
    CaptureInput(text: text, today: day, timeZone: utc, categoryIds: categories)
}

// MARK: - Arguments

@Test func theArgumentsAreExactlyTheDocumentedOnes() {
    let i = input("buy milk")
    let args = ClaudeCLI.arguments(for: i)
    #expect(args.count == 10)
    #expect(args[0] == "-p")
    #expect(args[1] == i.prompt)
    #expect(Array(args[2...]) == [
        "--output-format", "json",
        "--json-schema", CaptureSchema.make(categoryIds: categories).jsonString(),
        "--no-session-persistence",
        "--tools", "",
        "--safe-mode",
    ])
}

@Test func neverBareNeverAModel() {
    let args = ClaudeCLI.arguments(for: input())
    #expect(!args.contains("--bare"))
    #expect(!args.contains("--model"))
}

@Test func theSchemaIsOneCompactLine() throws {
    let schema = try #require(ClaudeCLI.arguments(for: input()).firstIndex(of: "--json-schema").map { ClaudeCLI.arguments(for: input())[$0 + 1] })
    #expect(!schema.contains("\n"))
    #expect(!schema.contains(": "))  // compact: no spaces after colons
    #expect(schema.contains("\"enum\":[\"personal\",\"work\"]"))
}

@Test func aQuoteInTheCaptureStaysInsideTheSingleArgument() {
    // Arguments are separate strings, so nothing typed can add a flag or break a quote.
    let args = ClaudeCLI.arguments(for: input("\" --model x ' $(rm -rf ~) \n--bare"))
    #expect(args.count == 10)
    #expect(args[1].contains("--model x"))
    #expect(!args.contains("--bare"))
}

// MARK: - Reading output

@Test(arguments: outputCases)
func readingOutput(name: String) throws {
    let stdout = try Data(contentsOf: cliFixtures.appendingPathComponent("\(name).stdout"))
    let expectedData = try Data(contentsOf: cliFixtures.appendingPathComponent("\(name).expected.json"))
    let expected = try #require(JSONSerialization.jsonObject(with: expectedData) as? [String: Any])

    do {
        let parsed = try ClaudeCLI.parse(stdout, categoryIds: categories)
        #expect(expected["error"] == nil, "\(name): should have failed")
        #expect(parsed.result.kind.rawValue == expected["kind"] as? String)
        #expect(parsed.result.title == expected["title"] as? String)
        #expect(parsed.result.confidence == (expected["confidence"] as? NSNumber)?.doubleValue)
        if let area = expected["area"] as? String { #expect(parsed.result.area == area) }
        #expect(parsed.diagnostics.totalCostUSD == (expected["cost"] as? NSNumber)?.doubleValue)
        #expect(parsed.diagnostics.inputTokens == (expected["input_tokens"] as? NSNumber)?.intValue)
        #expect(parsed.diagnostics.outputTokens == (expected["output_tokens"] as? NSNumber)?.intValue)
        #expect(parsed.diagnostics.durationMs == (expected["duration_ms"] as? NSNumber)?.intValue)
    } catch {
        let kind: String
        let message = error.errorDescription ?? ""
        switch error {
        case .cliReportedError: kind = "cliReportedError"
        case .noStructuredOutput: kind = "noStructuredOutput"
        case .invalidResult: kind = "invalidResult"
        case .unreadableOutput: kind = "unreadableOutput"
        default: kind = "other"
        }
        #expect(expected["error"] as? String == kind, "\(name): got \(error)")
        if let needle = expected["message_contains"] as? String {
            #expect(message.contains(needle), "\(name): “\(message)” should mention “\(needle)”")
        }
    }
}

@Test func theOutputFixturesAreFound() {
    #expect(outputCases.count >= 14)
}

// MARK: - Errors have sentences

@Test func everyErrorHasAReadableMessage() {
    let all: [ClassifierError] = [
        .cliNotFound, .cliReportedError("x"), .timedOut, .nonZeroExit(code: 2, stderr: "boom"), .nonZeroExit(code: 2, stderr: ""),
        .unreadableOutput("x"), .cancelled, .noStructuredOutput, .invalidResult("x"),
    ]
    for e in all { #expect(e.errorDescription?.isEmpty == false) }
    #expect(ClassifierError.nonZeroExit(code: 2, stderr: "boom").errorDescription?.contains("boom") == true)
    #expect(ClassifierError.nonZeroExit(code: 7, stderr: "").errorDescription?.contains("7") == true)
}

// MARK: - The classifier, with a fake process

/// Remembers how it was called and answers with whatever the test says.
///
/// Swift note: `@unchecked Sendable` tells the compiler "I promise this is
/// safe to share between threads"; here a lock does the protecting.
private final class FakeRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(executable: URL, arguments: [String], folder: URL, timeout: Duration)] = []
    var calls: [(executable: URL, arguments: [String], folder: URL, timeout: Duration)] { lock.withLock { _calls } }
    var folderExistedDuringRun = false
    let answer: @Sendable (URL) throws -> ProcessOutput

    init(_ answer: @escaping @Sendable (URL) throws -> ProcessOutput) { self.answer = answer }

    func run(executable: URL, arguments: [String], workingDirectory: URL, timeout: Duration) async throws(ProcessRunError) -> ProcessOutput {
        lock.withLock {
            _calls.append((executable, arguments, workingDirectory, timeout))
            var isDirectory: ObjCBool = false
            folderExistedDuringRun =
                FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && ((try? FileManager.default.contentsOfDirectory(atPath: workingDirectory.path)) ?? ["x"]).isEmpty
        }
        do {
            return try answer(workingDirectory)
        } catch let error as ProcessRunError {
            throw error
        } catch {
            throw .launchFailed("\(error)")
        }
    }
}

private let claudeURL = URL(fileURLWithPath: "/fake/bin/claude")
private let goodStdout = Data(#"{"type":"result","is_error":false,"total_cost_usd":0.5,"structured_output":{"kind":"task","title":"Call the dentist","confidence":0.9}}"#.utf8)

private func classifier(_ runner: FakeRunner, found: Bool = true, timeout: Duration = .seconds(60)) -> ClaudeCLIClassifier {
    ClaudeCLIClassifier(locateExecutable: { found ? claudeURL : nil }, runner: runner, timeout: timeout)
}

@Test func aGoodAnswerBecomesACaptureResult() async throws {
    let runner = FakeRunner { _ in ProcessOutput(stdout: goodStdout, stderr: Data(), exitCode: 0) }
    let result = try await classifier(runner).classify(input())
    #expect(result.kind == .task)
    #expect(result.title == "Call the dentist")
    #expect(result.area == "personal")
    // The runner got the program, the documented arguments and the timeout.
    let call = try #require(runner.calls.first)
    #expect(call.executable == claudeURL)
    #expect(call.arguments == ClaudeCLI.arguments(for: input()))
    #expect(call.timeout == .seconds(60))
}

@Test func theToolRunsInAnEmptyFolderThatIsRemovedAfterwards() async throws {
    let runner = FakeRunner { _ in ProcessOutput(stdout: goodStdout, stderr: Data(), exitCode: 0) }
    _ = try await classifier(runner).classify(input())
    let folder = try #require(runner.calls.first?.folder)
    #expect(runner.folderExistedDuringRun)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    // Also when it fails.
    let failing = FakeRunner { _ in throw ProcessRunError.timedOut }
    _ = try? await classifier(failing).classify(input())
    #expect(!FileManager.default.fileExists(atPath: try #require(failing.calls.first?.folder).path))
}

@Test func diagnosticsAreReported() async throws {
    let seen = Locked<ClassifierDiagnostics?>(nil)
    let runner = FakeRunner { _ in ProcessOutput(stdout: goodStdout, stderr: Data(), exitCode: 0) }
    let c = ClaudeCLIClassifier(locateExecutable: { claudeURL }, runner: runner, onDiagnostics: { seen.set($0) })
    _ = try await c.classify(input())
    #expect(seen.get()?.totalCostUSD == 0.5)
}

final class Locked<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func set(_ new: T) { lock.withLock { value = new } }
    func get() -> T { lock.withLock { value } }
}

@Test func noProgramMeansNotFoundAndNothingRuns() async {
    let runner = FakeRunner { _ in ProcessOutput(stdout: goodStdout, stderr: Data(), exitCode: 0) }
    await #expect(throws: ClassifierError.cliNotFound) { try await classifier(runner, found: false).classify(input()) }
    #expect(runner.calls.isEmpty)
}

@Test func aProgramThatVanishedIsNotFoundToo() async {
    let runner = FakeRunner { _ in throw ProcessRunError.executableNotFound }
    await #expect(throws: ClassifierError.cliNotFound) { try await classifier(runner).classify(input()) }
}

@Test func anotherLaunchFailureKeepsItsReason() async {
    let runner = FakeRunner { _ in throw ProcessRunError.launchFailed("Permission denied") }
    await #expect(throws: ClassifierError.cliReportedError("Permission denied")) { try await classifier(runner).classify(input()) }
}

@Test func aCancelledRunIsCancelled() async {
    let runner = FakeRunner { _ in throw ProcessRunError.cancelled }
    await #expect(throws: ClassifierError.cancelled) { try await classifier(runner).classify(input()) }
}

@Test func aTimeoutIsATimeout() async {
    let runner = FakeRunner { _ in throw ProcessRunError.timedOut }
    await #expect(throws: ClassifierError.timedOut) { try await classifier(runner, timeout: .seconds(1)).classify(input()) }
    #expect(runner.calls.first?.timeout == .seconds(1))
}

@Test func aNonZeroExitShowsTheStartOfStderr() async {
    let long = String(repeating: "x", count: 1000)
    let runner = FakeRunner { _ in ProcessOutput(stdout: Data(), stderr: Data(("Error: " + long).utf8), exitCode: 2) }
    do {
        _ = try await classifier(runner).classify(input())
        Issue.record("should have thrown")
    } catch {
        guard case .nonZeroExit(let code, let stderr) = error else {
            Issue.record("got \(error)")
            return
        }
        #expect(code == 2)
        #expect(stderr.hasPrefix("Error: xxx"))
        #expect(stderr.count == 300)
    }
}

@Test func aFailureReportedAsJsonWithAnExitCodeKeepsItsMessage() async {
    let stdout = Data(#"{"type":"result","is_error":true,"result":"Not logged in"}"#.utf8)
    let runner = FakeRunner { _ in ProcessOutput(stdout: stdout, stderr: Data("noise".utf8), exitCode: 1) }
    await #expect(throws: ClassifierError.cliReportedError("Not logged in")) { try await classifier(runner).classify(input()) }
}

@Test func anAnswerThatComesWithAnExitCodeIsNotTrusted() async {
    let runner = FakeRunner { _ in ProcessOutput(stdout: goodStdout, stderr: Data(), exitCode: 1) }
    await #expect(throws: ClassifierError.nonZeroExit(code: 1, stderr: "")) { try await classifier(runner).classify(input()) }
}

@Test func outputThatIsNotJsonIsUnreadable() async {
    let runner = FakeRunner { _ in ProcessOutput(stdout: Data("Welcome to Claude".utf8), stderr: Data(), exitCode: 0) }
    await #expect(throws: ClassifierError.unreadableOutput("Welcome to Claude")) { try await classifier(runner).classify(input()) }
}

@Test func aBadAnswerIsInvalid() async {
    let stdout = Data(#"{"type":"result","is_error":false,"structured_output":{"kind":"task","title":"x","confidence":7}}"#.utf8)
    let runner = FakeRunner { _ in ProcessOutput(stdout: stdout, stderr: Data(), exitCode: 0) }
    do {
        _ = try await classifier(runner).classify(input())
        Issue.record("should have thrown")
    } catch {
        guard case .invalidResult(let why) = error else {
            Issue.record("got \(error)")
            return
        }
        #expect(why.contains("confidence"))
    }
}

// MARK: - Finding the program

private let home = "/Users/me"

@Test func theConfiguredPathWinsWhenItWorks() async {
    let found = await ClaudeLocator.locate(
        configured: "/custom/claude", home: home, isExecutable: { _ in true }, loginShell: { Issue.record("shell asked"); return nil })
    #expect(found?.path == "/custom/claude")
}

@Test func aBrokenConfiguredPathFallsBackToTheKnownPlaces() async {
    let found = await ClaudeLocator.locate(
        configured: "/custom/claude", home: home, isExecutable: { $0 == "/opt/homebrew/bin/claude" }, loginShell: { nil })
    #expect(found?.path == "/opt/homebrew/bin/claude")
}

@Test func knownPlacesAreTriedInOrderBeforeAskingAShell() async {
    #expect(ClaudeLocator.knownPaths(home: home) == [
        "/Users/me/.local/bin/claude", "/Users/me/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
    ])
    let found = await ClaudeLocator.locate(
        configured: nil, home: home, isExecutable: { $0.hasSuffix("/claude") && $0 != "/Users/me/.local/bin/claude" },
        loginShell: { Issue.record("shell asked"); return nil })
    #expect(found?.path == "/Users/me/.claude/local/claude")
}

@Test func aBlankConfiguredPathIsNoPath() async {
    let found = await ClaudeLocator.locate(configured: "  ", home: home, isExecutable: { $0 == "/usr/local/bin/claude" }, loginShell: { nil })
    #expect(found?.path == "/usr/local/bin/claude")
}

@Test func theLoginShellIsTheLastResortAndItsLastLineCounts() async {
    let found = await ClaudeLocator.locate(
        configured: nil, home: home, isExecutable: { $0 == "/somewhere/else/claude" },
        loginShell: { "Last login: today\n/somewhere/else/claude\n" })
    #expect(found?.path == "/somewhere/else/claude")
}

@Test func aShellAnswerThatIsNotAnExecutablePathIsIgnored() async {
    // `command -v` can print an alias definition or nothing; neither is a program.
    for answer in ["alias claude='x'", "", "claude", "/not/there/claude"] {
        let found = await ClaudeLocator.locate(configured: nil, home: home, isExecutable: { _ in false }, loginShell: { answer })
        #expect(found == nil, "\(answer)")
    }
}

// MARK: - Notes can't be filed into the Tasks folder

@Test func theTasksFolderIsReserved() {
    #expect(VaultPath.reservedFolders == ["Notes/Tasks"])
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.file("Notes/Tasks/Idea.md") }
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.folder("notes/TASKS/Sub") }
    #expect(throws: VaultPathError.self) { try VaultPath.resolve(file: "Notes/Tasks/Idea.md", in: FileManager.default.temporaryDirectory) }
}

@Test func aDifferentTasksFolderCanBePassedIn() throws {
    #expect(throws: VaultPathError.reservedFolder("Work/Todo")) { try VaultPath.file("work/todo/x.md", reserved: ["Work/Todo"]) }
    // The default isn't reserved then.
    #expect(try VaultPath.file("Notes/Tasks/x.md", reserved: ["Work/Todo"]) == "Notes/Tasks/x.md")
    #expect(try VaultPath.file("Notes/Tasks/x.md", reserved: []) == "Notes/Tasks/x.md")
}

@Test func theTasksFolderCannotBeReachedWithLookAlikeLetters() {
    // On a Mac `Taſks` (long s) is the folder `Tasks`: the file system folds it.
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.file("Notes/Ta\u{17F}ks/X.md") }
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.file("NOTES/TA\u{17F}KS/X.md") }
    // Different spelling of an accent: still one folder.
    #expect(throws: VaultPathError.reservedFolder("Café/Tasks")) { try VaultPath.file("Cafe\u{301}/tasks/X.md", reserved: ["Café/Tasks"]) }
}

@Test func anAliasOfTheTasksFolderIsRefusedToo() throws {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-alias-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: vault) }
    let fm = FileManager.default
    try fm.createDirectory(at: vault.appendingPathComponent("Notes/Tasks"), withIntermediateDirectories: true)
    try fm.createDirectory(at: vault.appendingPathComponent("Wiki"), withIntermediateDirectories: true)
    // `Wiki/shortcut` is an alias of `Notes/Tasks`: the text looks harmless.
    try fm.createSymbolicLink(atPath: vault.appendingPathComponent("Wiki/shortcut").path, withDestinationPath: "../Notes/Tasks")
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.resolve(file: "Wiki/shortcut/X.md", in: vault) }
    #expect(throws: VaultPathError.reservedFolder("Notes/Tasks")) { try VaultPath.resolve(folder: "Wiki/shortcut", in: vault) }
    #expect((try? VaultPath.resolve(file: "Wiki/Fine.md", in: vault)) != nil)
}
