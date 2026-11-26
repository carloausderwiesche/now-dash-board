// Putting the classifier together for the Mac app: which `claude` to run, and
// the classifier that runs it. No screen uses it yet; the debug launch
// argument `-classifyDemo` does (DebugClassify.swift).

#if os(macOS)
    import Foundation
    import NowboardKit

    enum ClaudeSupport {
        /// The real home folder, from the user database (like `TauriSettings`).
        static var home: String {
            getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        }

        /// The `claude` program to run: the device setting, the usual places, a login shell.
        static func locate(configured: String?) async -> URL? {
            await ClaudeLocator.locate(
                configured: configured, home: home,
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                loginShell: { await ProcessRunner.loginShellAnswer() })
        }

        /// A classifier that uses the real tool. `claudePath` is read each time
        /// (a closure), so a changed setting counts without restarting.
        static func classifier(
            claudePath: @escaping @Sendable () -> String?, timeout: Duration = .seconds(60),
            onDiagnostics: (@Sendable (ClassifierDiagnostics) -> Void)? = nil
        ) -> ClaudeCLIClassifier {
            ClaudeCLIClassifier(
                locateExecutable: { await locate(configured: claudePath()) }, runner: ProcessRunner(), timeout: timeout,
                onDiagnostics: onDiagnostics)
        }
    }
#endif
