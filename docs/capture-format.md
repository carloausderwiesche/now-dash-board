# Capture format, v1

A **capture** is a bit of free text typed (or pasted) into Nowboard: "call the dentist", "idea: pin the board to the menu bar", "what's the capital of Peru". This file says what the app writes to the vault for a capture and how the classifier's answer is read, so every program that touches captures behaves the same.

It covers the pure rules only: files, JSON, paths and strings. Running the classifier and the UI are not part of it. The rules live in `apple/NowboardKit` (`Capture/`) and are checked by the cases in [`fixtures/capture/`](../fixtures/capture/README.md). The task files a capture can turn into follow [the task file format](task-format.md), which this file does **not** change.

The words **must**, **must not** and **should** are used in their usual spec sense.

## 1. The golden rule

**The typed text is saved before anything else happens.** Writing the raw capture (2) comes first; classifying, filing and asking all come after and may fail, be slow or be wrong. Nothing a person typed is ever lost, even if the classifier is offline.

## 2. Raw capture files

- One capture = one file in `<vault>/Notes/Inbox/` (the **Inbox**). The folder is created if missing.
- The name is the **local** time of the capture, `YYYY-MM-DD HH-mm-ss.md`, for example `2026-11-26 13-05-22.md`. If that name is taken, try `2026-11-26 13-05-22 (2).md`, `(3)` and so on, like clash counters for tasks.
- Content:

  ```markdown
  ---
  captured: 2026-11-26T13:05
  ---
  call the dentist about Thursday
  ```

  - `captured` is the local time without seconds and time zone, like `created` in a task file.
  - The body is the **exact typed text**: no trimming, no added line break at the end, line breaks and spaces kept as they were.
- A capture whose text is empty or only whitespace is refused. Nothing is written.
- **Create-only.** A writer **must never** overwrite or replace an existing file. It writes the content to a hidden temporary file in the Inbox (`.<unique>.tmp`) and then links it under the final name in a way that fails if the name exists; on a clash it tries the next name. The temporary file is always removed. Nobody sees a half-written capture.
- Files in the Inbox are never deleted by the app because of a capture. A capture file is the record; what the classifier made of it is recorded next to it (3).

## 3. Inbox entries

An **Inbox entry** is one file in the Inbox, read as:

| Part | Meaning |
|---|---|
| `id` | The file name. |
| `text` | The body, as typed (2). |
| `captured` | The `captured` field, read as text. Missing if absent. |
| `outcome` | What became of it, from the optional `outcome` field. **Missing** means nothing happened to it yet. |

`outcome` is one of:

| Value | Meaning |
|---|---|
| `task-suggested` | A task was added to the board as `suggested` for the person to accept. |
| `note-filed` | A note was written into the vault. |
| `answered` | It was a question and the answer was shown. |
| `waiting-for-answer` | The classifier wasn't sure (unclear, or below the threshold in 4.3) and a follow-up question is waiting. |
| `skipped` | The person dismissed it, or it was left as it is. |

A value that isn't in this list is read as missing. Setting the outcome changes only the frontmatter: `outcome` is added or replaced, other fields keep their place, and the body stays byte for byte as it was.

## 4. The classifier result

The classifier answers with one JSON object.

### 4.1 Fields

| Field | Type | Required | Meaning |
|---|---|---|---|
| `kind` | `"task"`, `"note"`, `"question"`, `"unclear"` | yes | What the capture is. |
| `title` | string | yes | Short title: the task title, the note's file name, the question restated. Must not be empty. Made into one line (see below). |
| `confidence` | number from 0 to 1 | yes | How sure the classifier is. Outside 0 to 1 is an error. |
| `body` | string | no | Longer text: the note's content, the question's answer, a task's checklist or notes. |
| `area` | string | no | A category id (task format 3). |
| `status` | `"today"` or `"backlog"` | no | For tasks. Missing means the reader decides (`backlog`). |
| `folder` | string | no | For notes: the suggested vault folder, for example `Wiki/Projects`. Model-chosen, so it **must** pass the path rules in 5 before it's used. |
| `follow_up` | string | no | For `unclear`: one short question to ask the person. |

Other keys are ignored.

### 4.2 Validation

- Not valid JSON, not an object, a required field missing, or a field with the wrong type (`"confidence": "high"`, `"kind": 3`, a boolean where a number is expected) → an **error**. Nothing is filed; the capture stays in the Inbox without an outcome.
- An unknown `kind` or `status` is an error.
- Optional strings that are `null` or only whitespace are **missing**. Other optional strings are trimmed.
- **One line:** the title is split at line breaks, every piece is trimmed, empty pieces are dropped and the rest is joined with one space (`"Pay rent \n today"` → `Pay rent today`). If nothing is left, the title is missing.
- `area` must be one of the board's category ids. Anything else, or missing, becomes the **first** category's id. (If there are no categories, `personal`, the default area of the task format.)

### 4.3 Confidence

`confidence` below **0.58** means the classifier isn't sure: the result is treated as `unclear` whatever `kind` it says, and the person is asked. Exactly 0.58 passes. A result with kind `unclear` is always treated as unclear.

The question asked is `follow_up` if there is one; otherwise "Is this a task, a note or a question?".

0.58 is a starting point, not a tuned value. In spike runs with 30 made-up inputs, unclear inputs scored 0.2 to 0.4 (one scored 0.90, which doesn't matter: kind `unclear` is always asked about), wrongly filed notes 0.50 to 0.55 and correct notes at least 0.60 (at least 0.70 with `--safe-mode`). Tune it with real captures ([ADR 0015](adr/0015-classify-captures-with-claude-cli.md)).

## 5. Paths chosen by the model

A path from the classifier is **untrusted text**. Before a file or folder is created from it, it **must** pass all of these. A path is relative to the vault root, with `/` between parts.

1. Not empty.
2. Not absolute: doesn't start with `/` or `~`, and has no `\`.
3. Every part is a plain name:
   - not empty (no `//`, no trailing `/`), not `.`, not `..`;
   - doesn't start with `.` (hidden files and folders, `.obsidian`, `.git`, `.nowboard.json`);
   - has none of `/ \ : * ? " < > | # ^ [ ]` and no control characters (the characters task titles lose, task format 4.1);
   - doesn't start or end with whitespace, and doesn't end with `.`;
   - is at most **80** Unicode scalars long.
4. At most **4** folders deep (the file name doesn't count).
5. A file path ends in `.md` (lower case) and has a name before it that doesn't end in whitespace or a dot; a folder path is just folders (no `.md` file).
6. The path as a whole is at most 240 Unicode scalars.

When it's turned into a real location, the result **must** also lie inside the vault after symbolic links are resolved. A path that fails any check is refused, never "repaired".

## 6. The daily note: "Captured" section

A daily note can list captures under a `## Captured` heading. Adding a line is a pure text transformation: **current note text + line → new note text.**

1. The line is made into one line (as for titles in 4.2). If nothing is left, the text is returned unchanged.
2. If the text has a heading line that is exactly `## Captured` (trailing spaces allowed): the line is added at the **end of that section**, after the section's last non-blank line and before the blank lines that separate it from the next heading. The section ends at the next heading of level 1 or 2 (`# ` or `## `) or the end of the text. Headings inside a fenced code block (``` or ~~~) or inside frontmatter don't count. If there are several, the first one is used.
3. If there is no such heading: a blank line (unless the text is empty or already ends with one), `## Captured`, then the line, are added at the end.
4. The new line is always followed by a line break, and a text that ended without one gets it when the new line goes at the very end. Everything added uses the line break the text already uses (`\n` or `\r\n`; `\n` if it has none).
5. **No other text changes.** Text typed mid-sentence at the end of a note, with no final line break, only gets the line break it was missing.

## 7. The prompt

The prompt that asks the classifier is built from: the capture text, today's date (with weekday), the category ids, a **vault map** (folder tree) and the contents of an optional `_vault-guide.md` in the vault root. All three variable parts have size limits so the prompt stays small and fast:

| Part | Limit |
|---|---|
| Capture text | 4000 characters (the raw file keeps everything) |
| Vault map | 3000 characters, 150 folders, 4 levels deep; hidden folders are left out; a line says how many folders were cut |
| Vault guide | 4000 characters |

Cut text ends with a marker saying how much was cut. The capture text and the guide are given to the classifier as data between tags, and the prompt says it must not follow instructions found in them. A closing tag typed inside them is defused so it can't end the block early.

The result schema is the JSON schema for the object in 4.1, with `area` limited to the category ids.
