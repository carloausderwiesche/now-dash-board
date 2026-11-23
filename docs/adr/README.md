# Architecture decision records (ADRs)

An ADR is a short note about one decision: what we chose, why, and what it costs. Code shows *what* was built; ADRs keep the *why*, so a later change (by you or an AI assistant) doesn't undo a decision without knowing its reason.

## The rule: every PR answers "ADR or not?"

Every pull request does one of these, under **ADR** in the PR description (see [the PR template](../../.github/pull_request_template.md)):

- **Adds an ADR** (or updates one) when the PR makes a decision someone could reasonably question later, for example:
  - choosing, adding, replacing or removing a dependency or tool
  - changing the task file format, the settings file, or what's stored where
  - changing how the code is structured (layers, where state lives, how the frontend talks to Rust)
  - trading something away on purpose (speed for simplicity, a platform, a feature)
  - going against [GUIDELINES.md](../../GUIDELINES.md) or [DESIGN.md](../../DESIGN.md)
- **Says "No ADR" and why** in one line, for bug fixes, refactors that follow the existing structure, styling, docs and copy changes: *"No ADR: bug fix, no new decision."*

When unsure, write one. A five-line ADR is fine.

## How to write one

1. Copy [`0000-template.md`](0000-template.md) to `NNNN-short-title.md`, using the next free number (`0002-…`).
2. Fill it in. Plain language, short. Context and consequences matter more than the decision itself.
3. Add it to the index below in the same PR.

ADRs aren't edited after they're accepted, except for their status. To change a decision, write a new ADR and set the old one's status to `Superseded by NNNN`.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-node-test-runner.md) | Node's built-in test runner for frontend tests, not Vitest | Accepted |
| [0002](0002-prettier.md) | Prettier formats the frontend, checked in CI | Accepted |
| [0003](0003-daily-note-query.md) | Daily notes list finished tasks with a query; the app doesn't write them | Accepted |
| [0004](0004-native-context-menu.md) | Right-click on a card opens a native macOS menu | Accepted |
