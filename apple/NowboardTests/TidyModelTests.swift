// The Tidy vault flow with a fake AI against a temporary vault: nothing changes until the person
// approves, refused operations can't be approved, and changes can be undone.

#if os(macOS)
    import Foundation
    import NowboardKit
    import Testing

    @testable import Nowboard

    private struct FakeAdvisor: TidyAdvisor {
        let operations: [VaultOperation]
        let failure: ClassifierError?
        func propose(_ input: TidyInput) async throws(ClassifierError) -> [VaultOperation] {
            if let failure { throw failure }
            return operations
        }
    }

    private func makeVault(_ files: [String: String]) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("nowboard-tidym-\(UUID().uuidString)")
        for dir in [".obsidian", "Notes/Tasks", "Notes/Inbox", "Wiki/Ideas"] {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for (path, text) in files {
            let url = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return vault
    }

    private func read(_ vault: URL, _ path: String) -> String? { try? String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8) }

    @MainActor private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private let inboxNote = "---\nfrom: '[[Notes/Inbox/x]]'\n---\n# Plan\nbody\n"

    @MainActor @Test func nothingChangesUntilThePersonApproves() async throws {
        let vault = try makeVault(["Notes/Inbox/Plan.md": inboxNote])
        defer { try? FileManager.default.removeItem(at: vault) }
        let move = VaultOperation(kind: .move, path: "Notes/Inbox/Plan.md", to: "Wiki/Ideas/Plan.md", reason: "ideas")
        let model = TidyModel(changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: [move], failure: nil))
        model.propose()
        await eventually { model.phase == .review }
        #expect(model.items.count == 1 && model.items[0].approved && model.items[0].problem == nil)
        // The list is only a proposal: the note is still where it was.
        #expect(read(vault, "Notes/Inbox/Plan.md") != nil && read(vault, "Wiki/Ideas/Plan.md") == nil)
        model.cancel()
        #expect(model.phase == .idle)
        #expect(read(vault, "Notes/Inbox/Plan.md") != nil)
    }

    @MainActor @Test func approvedOperationsAreDoneAndCanBeUndone() async throws {
        let vault = try makeVault(["Notes/Inbox/Plan.md": inboxNote, "Wiki/Ideas/Other.md": "[[Notes/Inbox/Plan]]\n"])
        defer { try? FileManager.default.removeItem(at: vault) }
        let move = VaultOperation(kind: .move, path: "Notes/Inbox/Plan.md", to: "Wiki/Ideas/Plan.md")
        let model = TidyModel(changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: [move], failure: nil))
        model.propose()
        await eventually { model.phase == .review }
        model.applyApproved()
        await eventually { model.phase == .idle && !model.recent.isEmpty }
        #expect(read(vault, "Wiki/Ideas/Plan.md") == inboxNote)
        #expect(read(vault, "Wiki/Ideas/Other.md") == "[[Wiki/Ideas/Plan]]\n")  // the link followed
        #expect(model.message?.contains("Done: 1") == true)
        #expect(model.recent.first?.undone == false)

        model.undo(try #require(model.recent.first?.id))
        await eventually { model.recent.first?.undone == true }
        #expect(read(vault, "Notes/Inbox/Plan.md") == inboxNote)
        #expect(read(vault, "Wiki/Ideas/Other.md") == "[[Notes/Inbox/Plan]]\n")
        #expect(read(vault, "Wiki/Ideas/Plan.md") == nil)
    }

    @MainActor @Test func aRefusedOperationCannotBeApprovedOrApplied() async throws {
        let vault = try makeVault(["Notes/Inbox/Plan.md": inboxNote])
        defer { try? FileManager.default.removeItem(at: vault) }
        // A hostile proposal: outside the vault, and into the Tasks folder.
        let bad = [
            VaultOperation(kind: .move, path: "Notes/Inbox/Plan.md", to: "../../Library/Plan.md"),
            VaultOperation(kind: .move, path: "Notes/Inbox/Plan.md", to: "Notes/Tasks/Plan.md"),
            VaultOperation(kind: .move, path: "Notes/Inbox/Nope.md", to: "Wiki/Ideas/Nope.md"),
        ]
        let model = TidyModel(changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: bad, failure: nil))
        model.propose()
        await eventually { model.phase == .review }
        #expect(model.items.allSatisfy { $0.problem != nil && !$0.approved })
        #expect(model.approvedCount == 0)
        model.toggle(model.items[0].id)  // can't be switched on
        #expect(model.approvedCount == 0)
        model.applyApproved()  // nothing approved: nothing happens
        #expect(model.phase == .review)
        #expect(read(vault, "Notes/Inbox/Plan.md") == inboxNote)
    }

    @MainActor @Test func theApprovalCanBeSwitchedOffPerOperation() async throws {
        let vault = try makeVault(["Notes/Inbox/A.md": inboxNote, "Notes/Inbox/B.md": inboxNote])
        defer { try? FileManager.default.removeItem(at: vault) }
        let ops = [
            VaultOperation(kind: .move, path: "Notes/Inbox/A.md", to: "Wiki/Ideas/A.md"),
            VaultOperation(kind: .move, path: "Notes/Inbox/B.md", to: "Wiki/Ideas/B.md"),
        ]
        let model = TidyModel(changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: ops, failure: nil))
        model.propose()
        await eventually { model.phase == .review }
        model.toggle(model.items[1].id)  // not B
        #expect(model.approvedCount == 1)
        model.applyApproved()
        await eventually { model.phase == .idle && !model.recent.isEmpty }
        #expect(read(vault, "Wiki/Ideas/A.md") != nil && read(vault, "Notes/Inbox/B.md") != nil)
    }

    @MainActor @Test func aFailingAIShowsAnErrorAndChangesNothing() async throws {
        let vault = try makeVault(["Notes/Inbox/Plan.md": inboxNote])
        defer { try? FileManager.default.removeItem(at: vault) }
        let model = TidyModel(
            changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: [], failure: .timedOut))
        model.propose()
        await eventually { if case .failed = model.phase { true } else { false } }
        if case .failed(let why) = model.phase { #expect(why.contains("too long")) } else { Issue.record("expected failed") }
        #expect(read(vault, "Notes/Inbox/Plan.md") == inboxNote)
    }

    @MainActor @Test func anEmptyInboxMeansNothingToAskTheAIAbout() async throws {
        let vault = try makeVault([:])
        defer { try? FileManager.default.removeItem(at: vault) }
        let model = TidyModel(
            changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: [], failure: .cliNotFound))
        model.propose()
        await eventually { model.message != nil }
        #expect(model.phase == .idle)  // the AI was never asked, so its failure never showed
        #expect(model.message?.contains("Nothing to tidy") == true)
    }

    @MainActor @Test func anAnswerWithNoSuggestionsSaysSo() async throws {
        let vault = try makeVault(["Notes/Inbox/Plan.md": inboxNote])
        defer { try? FileManager.default.removeItem(at: vault) }
        let model = TidyModel(changes: VaultChanges(config: VaultConfig(vault: vault)), advisor: FakeAdvisor(operations: [], failure: nil))
        model.propose()
        await eventually { model.message != nil }
        #expect(model.phase == .idle && model.message?.contains("nothing worth changing") == true)
    }
#endif
