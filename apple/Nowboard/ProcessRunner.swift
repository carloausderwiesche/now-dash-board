// Starting a program on the Mac and waiting for it (macOS only: iOS can't
// start other programs). It implements `ProcessRunning` from NowboardKit, so
// the classifier can be tested with a fake instead.

#if os(macOS)
    import Foundation
    import NowboardKit

    struct ProcessRunner: ProcessRunning {
        /// Runs `executable`, with its own working folder, until it ends or
        /// `timeout` passes (then it's stopped and `.timedOut` is thrown).
        ///
        /// The work happens on a background thread, so the screen never waits
        /// for it. Swift note: `async` functions can be paused while a slow
        /// thing happens; here a continuation hands the answer back when the
        /// background thread is done.
        func run(
            executable: URL, arguments: [String], workingDirectory: URL, timeout: Duration
        ) async throws(ProcessRunError) -> ProcessOutput {
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            // If the calling task is cancelled, the program is stopped too
            // (it would otherwise run on until the timeout).
            let handle = Handle()
            do {
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            continuation.resume(with: Result { try Self.runBlocking(executable, arguments, workingDirectory, seconds, handle) })
                        }
                    }
                } onCancel: {
                    handle.cancel()
                }
            } catch let error as ProcessRunError {
                throw error
            } catch {
                throw .launchFailed(error.localizedDescription)
            }
        }

        /// The blocking part. Runs on a background thread.
        private static func runBlocking(
            _ executable: URL, _ arguments: [String], _ folder: URL, _ timeout: Double, _ handle: Handle
        ) throws -> ProcessOutput {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = folder
            // Nothing to read from: a program that waits for input would wait forever.
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            do {
                try process.run()
            } catch {
                // The error for "no such program" is a Cocoa error with these codes.
                let code = (error as NSError).code
                if (error as NSError).domain == NSCocoaErrorDomain, code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError {
                    throw ProcessRunError.executableNotFound
                }
                throw ProcessRunError.launchFailed(error.localizedDescription)
            }
            // Now `cancel()` has something to stop (and stops it at once if it was called before).
            handle.started(process)

            // A pipe holds only about 64 KB. If we waited for the program to
            // end before reading, a program writing more would block on its
            // full pipe, and we'd block waiting for it: a deadlock. So both
            // pipes are read at the same time, each on its own thread.
            let stdout = Collected()
            let stderr = Collected()
            let readers = DispatchGroup()
            for (pipe, into) in [(out, stdout), (err, stderr)] {
                readers.enter()
                DispatchQueue.global().async {
                    into.set((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                    readers.leave()
                }
            }

            // The timeout: stop the program politely, and for good if it ignores that.
            let timedOut = Flag()
            let stopper = DispatchWorkItem {
                // Only if it's still running: one that just ended on its own isn't "too slow".
                guard process.isRunning else { return }
                timedOut.set()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stopper)

            process.waitUntilExit()
            stopper.cancel()
            // The readers end when the program's pipes close (it ended). Wait a
            // moment for them; a stray child holding a pipe open must not hang us.
            _ = readers.wait(timeout: .now() + 5)

            if handle.isCancelled { throw ProcessRunError.cancelled }
            if timedOut.isSet { throw ProcessRunError.timedOut }
            return ProcessOutput(stdout: stdout.get(), stderr: stderr.get(), exitCode: process.terminationStatus)
        }

        /// Asks a login shell where `claude` is: `/bin/zsh -lc 'command -v claude'`.
        /// A login shell reads the same startup files as Terminal, so it knows
        /// the PATH a Dock-started app doesn't get. Nil if it fails or takes over 5 s.
        static func loginShellAnswer() async -> String? {
            guard
                let output = try? await ProcessRunner().run(
                    executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v claude"],
                    workingDirectory: FileManager.default.temporaryDirectory, timeout: .seconds(5)),
                output.exitCode == 0
            else { return nil }
            return String(decoding: output.stdout, as: UTF8.self)
        }
    }

    /// Connects the waiting task with the running program, so a cancelled task
    /// can stop it. Behind a lock because two threads use it.
    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func started(_ process: Process) {
            lock.lock()
            self.process = process
            let stopNow = cancelled
            lock.unlock()
            if stopNow { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let running = process
            lock.unlock()
            running?.terminate()
        }

        var isCancelled: Bool { lock.withLock { cancelled } }
    }

    /// Data that one thread writes and another reads, behind a lock.
    /// Swift note: `@unchecked Sendable` = "trust me, it's thread-safe": the lock makes it so.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ new: Data) { lock.withLock { data = new } }
        func get() -> Data { lock.withLock { data } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
#endif
