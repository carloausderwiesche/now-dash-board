# 0020. The AI may tidy the vault, but never delete

- **Date:** 2026-11-27
- **Status:** Proposed

## Context

Captures ([the capture format](../capture-format.md)) put new notes in the best folder, but a vault gets messy: notes land in the Inbox when no folder fits, folders change, and names drift. The person wants the AI to help keep it organised. A model can be wrong, can be misled by the text it reads, and the notes are the person's own work, often years of it. So the question is what the AI may change, and what keeps a mistake from costing anything.

## Decision

Changes come in two steps, and the second is gated.

1. **Create-only (already so):** new notes go to the best folder and nothing existing is touched. The AI also keeps a short description of the folder structure, `_vault-guide.md`, current: it writes **only between two marker lines**, never the person's own text.
2. **Tidy-up, on request:** the AI may **propose** moves, renames, new first headings and appended text for the notes filed in the Inbox. It cannot delete or empty anything, and there is no operation for it. Each proposal is validated (the path rules, nothing overwritten, never a saved capture, never the Tasks folder, never the guide), shown to the person with its reason, and applied only when they approve. It runs only when they press **Tidy vault**, never in the background, never during a focus session.

What makes every change safe ([vault changes](../vault-changes.md), section 4):
- the original of every touched note is copied to a hidden history folder first, create-only;
- every change is written to an append-only log;
- any change can be undone, but only while every touched file is still exactly as the change left it (a SHA-256 check), otherwise nothing is changed and the person is told;
- a failure half way puts everything back;
- links to a moved note are rewritten by a tested pure function that leaves ambiguous ones alone and never touches code.

## Alternatives considered

- **Fully automatic tidying in the background:** convenient, but a mistake would surface days later, and nobody would have seen the plan. The person asked for control over the vault.
- **Never move anything, only file new notes:** safest, but the Inbox fills up with notes that could not be placed.
- **Let the AI delete duplicates and empty notes:** tempting for a tidy vault, but a wrong deletion is exactly the unrecoverable mistake. A history copy could restore it, but only if the history is never cleaned, so deletion is simply not offered.
- **Do the changes through Obsidian (a plugin or its URI scheme):** Obsidian would update links itself, but it needs a plugin, the app open, and is hard to test. File changes with our own link rewriting can be tested without Obsidian.

## Consequences

- A tidy-up never costs a note: the worst a wrong proposal can do is a move the person undoes. The price is that the history folder grows (one small copy per touched note) and that nothing is removed automatically.
- **Link rewriting is a promise we have to keep.** It covers wiki links only. Markdown links (`[text](Note.md)`), links Obsidian stores elsewhere, and plugins that index by path may not follow a move. Ambiguous links are left as they are and counted, so some links may need a look.
- A change to a note that is open in Obsidian can trigger Obsidian's own merge. Changes are written atomically after a re-read to keep that rare.
- The guide section is the AI's and the person's part is theirs; if the person damages the markers, the app stops writing there and says so.
- Revisit if the person wants automatic runs, or if the Inbox-only scope turns out too small to be useful.
