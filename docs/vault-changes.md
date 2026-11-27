# Vault changes, v1

How the AI may change notes the person already has, and the safeguards. It builds on [the capture format](capture-format.md), which says how a new note is filed. This file covers three things: the vault guide, tidy-up operations (moves and edits), and what is kept so every change can be undone.

The rules are in `apple/NowboardKit` (`Vault/`) and checked by `fixtures/vault-changes/` and the tests next to it. The words **must**, **must not** and **should** are used in their usual spec sense. The decision is recorded in [ADR 0020](adr/0020-the-ai-may-tidy-the-vault-but-never-delete.md).

## 1. The vault guide

`_vault-guide.md` in the vault root is a short description of the folders and habits of the vault. The classifier reads it when it files a note ([capture format](capture-format.md), 7).

- The file has the **person's part** and **one section for the AI**, between the two lines `<!-- nowboard:guide-start -->` and `<!-- nowboard:guide-end -->` (each alone on its line). The first line inside the section is a fingerprint, `<!-- nowboard:tree=<hex> -->`, of the folder map the text was written for.
- The app **must only change what is between the markers**. Everything else, however odd (Windows line breaks, a BOM), stays byte for byte. A file without a section gets one at the end, after a blank line. A new file starts with a heading and a note saying where to write.
- A **start marker with no end marker** is a half section: the app writes nothing and says so. The text after it may be the person's.
- The AI's text is cut to **2000 characters** (at a line break), and `<!--` and `-->` are removed from it, so it can't open a comment or write a marker.
- **When it is updated:** after a note is filed, if the folder map has changed since the fingerprint. Otherwise nothing is asked. The AI gets the folder map, its earlier text and the person's part as data, and its answer is `{"guide": "…"}`. The file is re-read right before it is written and written atomically. If the call fails, filing the note is not affected.

## 2. Operations

The AI never changes anything itself. It **proposes** a list of operations; each is checked, shown to the person, and done only on their approval. Four kinds exist, and there is **no delete**:

| `op` | Parts | Does |
|---|---|---|
| `move` | `path`, `to` | Moves a note to a new path (the name may change). Links to it are updated (3). |
| `rename` | `path`, `name` | New file name in the same folder (the name is turned into a file name like a task title). Links are updated. |
| `append` | `path`, `text` | Adds the text at the end, after a blank line. At most 4000 characters, not empty. |
| `retitle` | `path`, `title` | Changes the first `# ` heading (outside frontmatter and code). One line, at most 200 characters, not empty. The note must have such a heading. |

Each may carry a `reason`, one sentence for the person. An answer holds at most **20** operations. One with an unknown kind or a missing part is dropped and counted, never repaired.

An operation is **refused** (nothing changes, nothing is logged) if:
- a path doesn't pass the path rules ([capture format](capture-format.md), 5): relative, no `..`, no hidden names, `.md`, not in the Tasks folder, no symbolic link out of the vault. This applies to the source and the destination;
- the source doesn't exist or isn't text;
- the source is `_vault-guide.md`, or a **saved capture** (a file with a `captured` field: it is the record of what was typed);
- the destination already exists (also in other capitals: a Mac doesn't tell them apart) or is the source: **nothing is ever overwritten**;
- the change would leave a note empty.

In v1 the AI is shown the notes **filed in the Inbox** (`Notes/Inbox/`, the fallback folder), up to 40, and proposes where they belong. It never sees the whole vault.

## 3. Links

Moving or renaming a note outside Obsidian doesn't update the links to it. The app does it for wiki links:

- A link `[[target]]`, `[[target#heading]]`, `[[target^block]]`, `[[target|alias]]` and the embed `![[target]]` (any combination) refers to the note if the target equals its path without `.md`, or ends with it at a folder boundary (`Wiki/Plan` for `Wiki/Ideas/Wiki/Plan.md`, `A/Plan`), or equals its file name. Capitals don't matter, a trailing `.md` is allowed, spaces around the target are ignored.
- If **more than one note** fits (two notes called `Plan`), only an exact full path counts. A plain name or partial path that could mean either is **ambiguous**: it is left alone and counted, never guessed.
- **After the move:** a link with a folder gets the new full path. A plain name stays when it still works (the name is unchanged and no other note has it now); otherwise it becomes the new name if that is unique, else the new full path. Alias, heading, block part, embed mark and `.md` are kept.
- **Never rewritten:** anything in a fenced code block (``` or ~~~, closed by a fence at least as long) and in inline code (`` `…` ``, ``` ``…`` ```). Links in frontmatter **are** rewritten (Obsidian treats them as links). Ordinary Markdown links (`[text](Note.md)`) are not understood and are left alone.
- The moved note's own links to itself are updated too. Line endings, and every other character, stay as they were.

Shared cases: `fixtures/vault-changes/link-rewrite.json`.

## 4. What is kept

Everything lives in the hidden folder `.nowboard/` in the vault root (Obsidian ignores folders that start with a dot).

- **History.** Before a note is changed or moved, its text goes to `.nowboard/history/<id>/<path>`, for every note the change touches (the note itself and each note whose links were rewritten). Create-only: an existing history file is never overwritten. The `<id>` is `YYYYMMDD-HHMMSS-xxxx` (local time and four hex digits), unique per change.
- **Log.** `.nowboard/changes.jsonl` is **append-only**: one JSON object per line, never rewritten or shortened. Two kinds of line:
  - `{"type": "change", "record": {...}}` with the `id`, `time`, the `operation`, `from` (the old path for a move), `files` (for each touched file: its `path` now, its original under `history`, and the `afterSha`, the SHA-256 of its text as the change left it) and the counts `linksChanged` and `linksAmbiguous`;
  - `{"type": "undo", "undoes": "<id>", "time": "…"}`.
- **Order of work.** Check everything, work out all new texts, save the originals, then change the files (the move first, then the notes with updated links, each re-read right before it is written and written atomically), then write the log line. If something fails half way, every touched file is put back from the originals, and nothing is logged.
- **Undo.** A change can be undone only if **every file it touched is still exactly as the change left it** (its SHA-256 equals `afterSha`), and the old path is free. Otherwise nothing is changed and the person is told which file was edited since. Undoing moves the note back and writes the saved originals back; the history stays. A change is undone once. Changes are undone newest first in practice, since a later change to the same note makes an earlier one fail the check.
- Undo only ever puts back what the app itself saved. The app never deletes a note.

## 5. When it runs

**Only when the person asks**, with a **Tidy vault** button on the Inbox page, never in the background and never while a focus session runs. The flow: the AI proposes, the person sees the list (each operation with its reason, and any refused ones with why), approves the ones they want, the app does them, and each shows an **Undo**.

## 6. Obsidian and files changed outside it

Obsidian watches the vault folder and re-reads files that change or move, so a moved or edited note shows up. What it does **not** do for a change made outside it is update the links to a moved note: its "automatically update internal links" setting only covers renames done inside Obsidian. That is why section 3 exists. A note that is open in Obsidian while a change is written may show Obsidian's own merge prompt; changes are written atomically and re-read first to keep that rare.
