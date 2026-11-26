// Debug builds only: `-classifyDemo "text"` classifies one capture with the
// real claude tool, prints the result (or the error) as JSON on stdout and
// quits. For trying the classifier without any screen:
//
//   Nowboard.app/Contents/MacOS/Nowboard -classifyDemo "call the dentist"
//
// Add `-claudePath /path/to/claude` to use a specific copy. This uses your
// Claude subscription for one call. It never touches a vault or the board.

#if DEBUG && os(macOS)
    import Foundation
    import NowboardKit

    enum DebugClassify {
        static func runIfAsked() {
            guard let text = DebugSnapshot.argument("classifyDemo") else { return }
            let path = DebugSnapshot.argument("claudePath") ?? DeviceSettings.load().claudePath
            // The category ids the board would send (the saved settings, or the defaults).
            let categories = DeviceSettings.load().categories.map(\.id)
            Task {
                let diagnostics = DiagnosticsBox()
                let classifier = ClaudeSupport.classifier(claudePath: { path }, onDiagnostics: { diagnostics.set($0) })
                let start = ContinuousClock.now
                var report: [String: Any] = ["input": text]
                do {
                    let result = try await classifier.classify(CaptureInput(text: text, categoryIds: categories))
                    report["result"] = [
                        "kind": result.kind.rawValue, "effective_kind": result.effectiveKind.rawValue,
                        "title": result.title, "body": result.body as Any, "area": result.area,
                        "status": result.status?.rawValue as Any, "folder": result.folder as Any,
                        "confidence": result.confidence, "follow_up": result.followUp as Any,
                        "needs_question": result.needsQuestion,
                    ]
                } catch {
                    report["error"] = (error as? ClassifierError)?.errorDescription ?? error.localizedDescription
                    report["error_case"] = "\(error)"
                }
                let elapsed = start.duration(to: .now).components
                report["seconds"] = ((Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 100).rounded() / 100
                if let d = diagnostics.get() {
                    report["cost_usd"] = d.totalCostUSD as Any
                    report["input_tokens"] = d.inputTokens as Any
                    report["output_tokens"] = d.outputTokens as Any
                }
                // `as Any` of an optional can leave `nil` inside; JSON needs NSNull.
                let clean = report.mapValues(unwrap)
                let data = try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys, .prettyPrinted])
                print(data.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
                fflush(stdout)
                exit(0)
            }
        }

        private static func unwrap(_ value: Any) -> Any {
            if let dict = value as? [String: Any] { return dict.mapValues(unwrap) }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional { return mirror.children.first.map { unwrap($0.value) } ?? NSNull() }
            return value
        }
    }

    private final class DiagnosticsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ClassifierDiagnostics?
        func set(_ new: ClassifierDiagnostics) { lock.withLock { value = new } }
        func get() -> ClassifierDiagnostics? { lock.withLock { value } }
    }
#endif
