// The "Tidy vault" button on the Inbox page, the app's side (docs/vault-changes.md).
// The AI proposes; the person looks at the list and approves; only then is anything changed.
// Every change can be undone from here. It never runs by itself.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Observation

    @MainActor @Observable
    final class TidyModel {
        enum Phase: Equatable {
            case idle
            /// Waiting for the AI.
            case proposing
            /// The list is on screen, waiting for the person's choice.
            case review
            case applying
            case failed(String)
        }

        /// One proposed operation, with why it can't be done if it can't.
        struct Item: Identifiable, Equatable {
            let id = UUID()
            var operation: VaultOperation
            /// Set when the checks refuse it: the item can't be approved.
            var problem: String?
            var approved: Bool
        }

        private(set) var phase: Phase = .idle
        private(set) var items: [Item] = []
        /// Operations in the AI's answer that were unusable.
        private(set) var dropped = 0
        /// A sentence about the last thing that happened (what was done, or why nothing was).
        private(set) var message: String?
        /// The latest changes in the log, newest first, each with Undo if it still can be.
        private(set) var recent: [ChangeRecord] = []

        @ObservationIgnored private let changes: VaultChanges
        @ObservationIgnored private let advisor: any TidyAdvisor

        init(changes: VaultChanges, advisor: any TidyAdvisor) {
            self.changes = changes
            self.advisor = advisor
            refreshRecent()
        }

        var approvedCount: Int { items.filter { $0.approved && $0.problem == nil }.count }

        /// Asks the AI what to tidy. Nothing is changed.
        func propose() {
            guard phase == .idle || phase == .review || isFailed else { return }
            phase = .proposing
            message = nil
            items = []
            let changes = changes, advisor = advisor
            Task {
                // The reading of notes and folders happens off the main thread.
                let input: TidyInput = await Task.detached {
                    let config = changes.config
                    let guide = try? String(contentsOf: config.vault.appendingPathComponent(VaultGuide.fileName), encoding: .utf8)
                    return TidyInput(
                        vaultMap: VaultMap.render(folders: VaultMap.scan(vault: config.vault)), guide: guide,
                        notes: VaultTidy.candidates(in: config, changes: changes))
                }.value
                guard !input.notes.isEmpty else {
                    phase = .idle
                    message = "Nothing to tidy: no notes are waiting in the Inbox folder."
                    return
                }
                do {
                    let operations = try await advisor.propose(input)
                    let checked = await Task.detached { operations.map { ($0, changes.problem(with: $0)) } }.value
                    items = checked.map { Item(operation: $0.0, problem: $0.1, approved: $0.1 == nil) }
                    dropped = 0
                    if items.isEmpty {
                        phase = .idle
                        message = "The AI found nothing worth changing."
                    } else {
                        phase = .review
                    }
                } catch {
                    phase = .failed(error.localizedDescription)
                }
            }
        }

        func toggle(_ id: UUID) {
            guard let i = items.firstIndex(where: { $0.id == id }), items[i].problem == nil else { return }
            items[i].approved.toggle()
        }

        /// Leaves the list without changing anything.
        func cancel() {
            items = []
            phase = .idle
        }

        /// Does the approved operations, one after the other. Each is checked again right before it runs.
        func applyApproved() {
            guard phase == .review else { return }
            let chosen = items.filter { $0.approved && $0.problem == nil }.map(\.operation)
            guard !chosen.isEmpty else { return }
            phase = .applying
            let changes = changes
            Task {
                let outcome: (done: Int, failures: [String]) = await Task.detached {
                    var done = 0
                    var failures: [String] = []
                    for operation in chosen {
                        do {
                            try changes.apply(operation)
                            done += 1
                        } catch {
                            failures.append("\(operation.summary): \(error.localizedDescription)")
                        }
                    }
                    return (done, failures)
                }.value
                items = []
                phase = .idle
                message = outcome.failures.isEmpty
                    ? "Done: \(outcome.done) change\(outcome.done == 1 ? "" : "s"). Each can be undone below."
                    : "Done: \(outcome.done). Not done: " + outcome.failures.joined(separator: "; ")
                refreshRecent()
            }
        }

        /// Takes a change back (if every file is still as it left it).
        func undo(_ id: String) {
            let changes = changes
            Task {
                let result: String? = await Task.detached {
                    do {
                        try changes.undo(id)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                message = result ?? "Undone."
                refreshRecent()
            }
        }

        func refreshRecent() {
            recent = Array(changes.records().prefix(8))
        }

        private var isFailed: Bool {
            if case .failed = phase { return true }
            return false
        }
    }
#endif
