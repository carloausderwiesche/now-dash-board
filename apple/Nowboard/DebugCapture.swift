// Debug builds only: `-captureDemo "text"` runs the whole capture pipeline
// with the real claude tool on a THROWAWAY vault the app creates in a
// temporary folder, prints what happened as JSON and quits:
//
//   Nowboard.app/Contents/MacOS/Nowboard -captureDemo "call the dentist"
//
// Your real vault and board are never touched. Add `-claudePath /path` to
// pick the claude program, and `-answer "text"` to also answer the question
// if the capture ends up waiting for one.

#if DEBUG && os(macOS)
    import Foundation
    import NowboardKit

    enum DebugCapture {
        static func runIfAsked() {
            guard let text = DebugSnapshot.argument("captureDemo") else { return }
            let path = DebugSnapshot.argument("claudePath") ?? DeviceSettings.load().claudePath
            let answer = DebugSnapshot.argument("answer")
            Task {
                let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-capture-demo-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: vault) }
                // A small vault: Obsidian's folder, the tasks folder and some folders to file notes in.
                for dir in [".obsidian", "Notes/Tasks", "Wiki/Projects", "Wiki/Ideas", "Wiki/People", "Daily", "Archive"] {
                    try? FileManager.default.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
                }
                try? #"{"folder": "Daily", "format": "YYYY-MM-DD"}"#.write(
                    to: vault.appendingPathComponent(".obsidian/daily-notes.json"), atomically: true, encoding: .utf8)
                let config = VaultConfig.load(vault: vault)
                let pipeline = CapturePipeline(
                    config: config, classifier: ClaudeSupport.classifier(claudePath: { path }), categoryIds: { ["personal", "work"] })

                var report: [String: Any] = ["input": text]
                let start = ContinuousClock.now
                do {
                    var result = try await pipeline.capture(text)
                    if let answer, result.entry.outcome == .waitingForAnswer {
                        report["answer"] = answer
                        result = try await pipeline.answer(result.entry.id, text: answer)
                    }
                    report["outcome"] = result.entry.outcome?.rawValue ?? "none (not classified)"
                    report["follow_up"] = result.entry.followUp ?? NSNull()
                    report["notice"] = result.entry.notice ?? NSNull()
                    report["problem"] = result.problem?.errorDescription ?? NSNull()
                    // Every file the pipeline made, with its text.
                    report["files"] = filesIn(vault)
                } catch {
                    report["error"] = error.localizedDescription
                }
                let elapsed = start.duration(to: .now).components
                report["seconds"] = ((Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 100).rounded() / 100
                let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                print(data.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
                fflush(stdout)
                exit(0)
            }
        }

        /// Path → text of every file in the demo vault (not the settings folder).
        private static func filesIn(_ vault: URL) -> [String: String] {
            var found: [String: String] = [:]
            let root = vault.resolvingSymlinksInPath().path
            guard let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
            for case let url as URL in walker where url.pathExtension == "md" {
                let relative = String(url.resolvingSymlinksInPath().path.dropFirst(root.count + 1))
                found[relative] = try? String(contentsOf: url, encoding: .utf8)
            }
            return found
        }
    }
#endif
