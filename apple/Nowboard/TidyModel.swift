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
        /// A focus session is running: nothing is proposed or applied until it ends (set by the dashboard).
        var sessionRunning = false
        /// A sentence about the last thing that happened (what was done, or why nothing was).
        private(set) var message: String?
        /// The latest changes in the log, newest first, each with Undo if it still can be.
        private(set) var recent: [ChangeRecord] = []

        @ObservationIgnored private let changes: VaultChanges
        @ObservationIgnored private let advisor: any TidyAdvisor
        /// Counts the proposals asked for: an answer that arrives after Cancel (or a newer request) is thrown away.
        @ObservationIgnored private var generation = 0

        init(changes: VaultChanges, advisor: any TidyAdvisor) {
            self.changes = changes
            self.advisor = advisor
            refreshRecent()
        }

        var approvedCount: Int { items.filter { $0.approved && $0.problem == nil }.count }

        /// Busy asking the AI or changing notes: nothing else (Undo included) starts meanwhile.
        var isBusy: Bool { phase == .proposing || phase == .applying }

        /// Asks the AI what to tidy. Nothing is changed.
        func propose() {
            guard !sessionRunning, phase == .idle || phase == .review || isFailed else { return }
            phase = .proposing
            message = nil
            items = []
            generation += 1
            let mine = generation
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
                guard mine == generation else { return }  // cancelled while reading
                guard !input.notes.isEmpty else {
                    phase = .idle
                    message = "Nothing to tidy: no notes are waiting in the Inbox folder."
                    return
                }
                // Only the notes the AI was shown may be changed. (The prompt says so too, but a note's text
                // can try to talk the AI into more; this is the check that doesn't depend on the AI.)
                let shown = Set(input.notes.map(\.path))
                do {
                    let proposal = try await advisor.propose(input)
                    let checked = await Task.detached {
                        proposal.operations.map { operation -> (VaultOperation, String?) in
                            guard shown.contains(operation.path) else { return (operation, "that note wasn't one of those shown to the AI") }
                            return (operation, changes.problem(with: operation))
                        }
                    }.value
                    guard mine == generation else { return }  // cancelled while the AI thought
                    // Moves, renames and new titles are pre-selected; adding text is never pre-selected.
                    items = checked.map { Item(operation: $0.0, problem: $0.1, approved: $0.1 == nil && $0.0.kind != .append) }
                    dropped = proposal.dropped
                    if items.isEmpty {
                        phase = .idle
                        message = proposal.dropped > 0
                            ? "The AI's answer had nothing usable (\(proposal.dropped) suggestion\(proposal.dropped == 1 ? "" : "s") dropped)."
                            : "The AI found nothing worth changing."
                    } else {
                        phase = .review
                    }
                } catch {
                    guard mine == generation else { return }
                    phase = .failed(error.localizedDescription)
                }
            }
        }

        func toggle(_ id: UUID) {
            guard let i = items.firstIndex(where: { $0.id == id }), items[i].problem == nil else { return }
            items[i].approved.toggle()
        }

        /// Leaves the list, or stops waiting for the AI, without changing anything.
        func cancel() {
            guard phase == .review || phase == .proposing else { return }
            generation += 1
            items = []
            phase = .idle
        }

        /// Does the approved operations, one after the other. Each is checked again right before it runs.
        func applyApproved() {
            guard phase == .review, !sessionRunning else { return }
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
            guard !isBusy else { return }
            phase = .applying  // blocks everything else until it's done
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
                phase = .idle
                refreshRecent()
            }
        }

        /// Reads the log off the main thread (it only ever grows).
        func refreshRecent() {
            let changes = changes
            Task {
                let latest = await Task.detached { Array(changes.records().prefix(8)) }.value
                recent = latest
            }
        }

        private var isFailed: Bool {
            if case .failed = phase { return true }
            return false
        }
    }
#endif
