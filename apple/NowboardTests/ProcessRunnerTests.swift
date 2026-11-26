// The real process runner, against harmless programs from /bin (macOS only).
// It must not hang on big output, must stop a slow program at the timeout
// and must report what it can't start. The classifier logic itself is tested
// with a fake runner in NowboardKit.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Testing

    @testable import Nowboard

    private let sh = URL(fileURLWithPath: "/bin/sh")
    private let tmp = FileManager.default.temporaryDirectory

    @Test func collectsOutputAndTheExitCode() async throws {
        let out = try await ProcessRunner().run(
            executable: sh, arguments: ["-c", "echo hello; echo oops >&2; exit 3"], workingDirectory: tmp, timeout: .seconds(10))
        #expect(String(decoding: out.stdout, as: UTF8.self) == "hello\n")
        #expect(String(decoding: out.stderr, as: UTF8.self) == "oops\n")
        #expect(out.exitCode == 3)
    }

    @Test func bigOutputOnBothPipesDoesNotDeadlock() async throws {
        // 2 MB on stdout and 2 MB on stderr: far more than a pipe holds (64 KB).
        let script = "head -c 2000000 /dev/zero | tr '\\0' a; head -c 2000000 /dev/zero | tr '\\0' b >&2"
        let out = try await ProcessRunner().run(executable: sh, arguments: ["-c", script], workingDirectory: tmp, timeout: .seconds(30))
        #expect(out.stdout.count == 2_000_000)
        #expect(out.stderr.count == 2_000_000)
        #expect(out.exitCode == 0)
    }

    @Test func aSlowProgramIsStoppedAtTheTimeout() async {
        let start = ContinuousClock.now
        await #expect(throws: ProcessRunError.timedOut) {
            try await ProcessRunner().run(executable: sh, arguments: ["-c", "sleep 30"], workingDirectory: tmp, timeout: .seconds(1))
        }
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test func aProgramThatIgnoresTheStopSignalIsKilled() async {
        let start = ContinuousClock.now
        // `trap '' TERM` ignores the polite stop; only the later kill works.
        await #expect(throws: ProcessRunError.timedOut) {
            try await ProcessRunner().run(
                executable: sh, arguments: ["-c", "trap '' TERM; while true; do sleep 1; done"], workingDirectory: tmp, timeout: .seconds(1))
        }
        #expect(start.duration(to: .now) < .seconds(15))
    }

    @Test func aMissingProgramIsReportedNotCrashed() async {
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/nonexistent/claude"), arguments: [], workingDirectory: tmp, timeout: .seconds(5))
            Issue.record("should have thrown")
        } catch {
            #expect(error == .executableNotFound)
        }
    }

    @Test func aCancelledTaskStopsTheProgram() async throws {
        let start = ContinuousClock.now
        let task = Task {
            try await ProcessRunner().run(executable: sh, arguments: ["-c", "sleep 30"], workingDirectory: tmp, timeout: .seconds(60))
        }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("should have thrown")
        } catch {
            #expect((error as? ProcessRunError) == .cancelled)
        }
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test func aProgramThatEndsByItselfIsNotATimeout() async throws {
        let out = try await ProcessRunner().run(executable: sh, arguments: ["-c", "echo ok"], workingDirectory: tmp, timeout: .seconds(30))
        #expect(out.exitCode == 0)
    }

    @Test func theProgramRunsInTheGivenFolderAndCannotWaitForInput() async throws {
        let dir = tmp.appendingPathComponent("nowboard-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // `cat` with nothing to read ends at once instead of waiting.
        let out = try await ProcessRunner().run(executable: sh, arguments: ["-c", "pwd -P; cat"], workingDirectory: dir, timeout: .seconds(10))
        let printed = String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // (`/var` is a link to `/private/var`, so compare the folder's own name.)
        #expect(URL(fileURLWithPath: printed).lastPathComponent == dir.lastPathComponent)
    }

    @Test func aLoginShellCanBeAsked() async {
        // On any Mac, `command -v ls` is `/bin/ls`, so this checks the plumbing without needing claude.
        let out = try? await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v ls"], workingDirectory: tmp, timeout: .seconds(10))
        let text = String(decoding: out?.stdout ?? Data(), as: UTF8.self)
        #expect(text.contains("/bin/ls"))
    }

    @Test func theDeviceSettingForTheClaudePathIsKeptAndOptional() throws {
        // An old saved settings file without the key still loads.
        let old = #"{"theme":"braun","density":"roomy","categories":[{"id":"work","name":"Work","color":"blue"}]}"#
        #expect(try JSONDecoder().decode(DeviceSettings.self, from: Data(old.utf8)).claudePath == nil)
        var settings = DeviceSettings()
        settings.claudePath = "/opt/homebrew/bin/claude"
        let again = try JSONDecoder().decode(DeviceSettings.self, from: JSONEncoder().encode(settings))
        #expect(again.claudePath == "/opt/homebrew/bin/claude")
    }
#endif
