// Debug builds only: a capture centre on a throwaway vault, with a scripted
// classifier instead of the real tool, so snapshots of the dashboard can show
// the capture bar, a question and the Inbox without any real data and
// without using the Claude subscription (`-demoCapture true`).

#if DEBUG && os(macOS)
    import Foundation
    import NowboardKit

    /// Answers by looking at the typed text, the way a real classifier might.
    struct ScriptedClassifier: Classifier {
        func classify(_ input: CaptureInput) async throws(ClassifierError) -> CaptureResult {
            let t = input.text.lowercased()
            let area = input.categoryIds.first ?? "personal"
            if input.answer != nil {
                return CaptureResult(kind: .task, title: "Call Mia", area: area, confidence: 0.9)
            }
            if t.contains("idea") || t.contains("note") {
                return CaptureResult(kind: .note, title: "Weekly review template", body: input.text, area: area, folder: "Wiki/Ideas", confidence: 0.85)
            }
            if t.hasSuffix("?") {
                return CaptureResult(kind: .question, title: input.text, area: area, confidence: 0.95)
            }
            if t.count < 6 {
                return CaptureResult(kind: .unclear, title: input.text, area: area, confidence: 0.2, followUp: "What about “\(input.text)”: something to do, or something to remember?")
            }
            return CaptureResult(kind: .task, title: input.text.prefix(1).uppercased() + input.text.dropFirst(), area: area, confidence: 0.9)
        }
    }

    @MainActor
    enum DebugDemoCapture {
        static func makeCenter() -> CaptureCenter {
            let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-demo-vault-\(UUID().uuidString)")
            for dir in [".obsidian", "Notes/Tasks", "Wiki/Ideas", "Wiki/Projects", "Daily"] {
                try? FileManager.default.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
            let clock = Clock()
            let center = CaptureCenter(
                config: VaultConfig(vault: vault), classifier: ScriptedClassifier(), categoryIds: { ["personal", "work", "freelance"] },
                now: { clock.next() })
            // A few captures to fill the Inbox; the last one stays as an open question
            // unless `-demoStrip` says otherwise.
            Task {
                for text in ["Send the invoice to the print shop", "Idea: a weekly review template", "What is the capital of Peru?", "Mia"] {
                    center.capture(text)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            return center
        }

        /// Each call is a minute later, so the demo captures get different file names without waiting.
        private final class Clock: @unchecked Sendable {
            private let lock = NSLock()
            private var minutes = 0
            func next() -> Date { lock.withLock { minutes += 1; return Date().addingTimeInterval(Double(minutes - 8) * 60) } }
        }
    }
#endif
