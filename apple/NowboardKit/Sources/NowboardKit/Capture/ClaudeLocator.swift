// Finding the `claude` program. A Mac app started from the Dock doesn't get
// the PATH of a Terminal window, so `claude` isn't simply "on the PATH":
// we look in the usual places, and as a last resort ask a login shell (the
// same shell setup Terminal uses) where it is.

import Foundation

public enum ClaudeLocator {
    /// Where the tool is usually installed, best first.
    public static func knownPaths(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
    }

    /// The tool to run, or nil.
    ///
    /// 1. `configured`: the path from the device settings, if there is one
    ///    and it's a program we can run.
    /// 2. The known places.
    /// 3. `loginShell`: asks a login shell for `command -v claude` and gives
    ///    its answer. Slow (it starts a shell), so it comes last.
    ///
    /// `isExecutable` and `loginShell` are passed in so this can be tested
    /// without a real disk or shell.
    public static func locate(
        configured: String?, home: String,
        isExecutable: (String) -> Bool,
        loginShell: () async -> String?
    ) async -> URL? {
        if let path = configured?.trimmedOrNil, isExecutable(path) {
            return URL(fileURLWithPath: path)
        }
        for path in knownPaths(home: home) where isExecutable(path) {
            return URL(fileURLWithPath: path)
        }
        // A login shell may print greetings before the answer: the path is the last line.
        if let output = await loginShell(),
            let path = output.split(whereSeparator: \.isNewline).last.map({ String($0).trimmingCharacters(in: .whitespaces) }),
            path.hasPrefix("/"), isExecutable(path)
        {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
