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
| `outcome` | What became of it, from the optional `outcome` field. **Missing** means nothing happened to it yet (not classified: see 10). |
| `follow_up` | The question waiting for the person (`waiting-for-answer`). |
| `task` | The task file the app made (`task-suggested`): a file name in the Tasks folder. |
| `task_sha` | The SHA-256 of the task file as written (Undo only deletes it if it is still exactly that). |
| `note`, `note_sha` | The note the app filed (`note-filed`): its path relative to the vault, and the SHA-256 of its text as written. |
| `daily_note`, `daily_line` | The daily note and the exact line the app added to it. |
| `notice` | Something the person should know (see 9). |

Only a file with a `captured` field is a capture. A file dropped into the Inbox by hand, or a note the app filed there (9), has none and is never classified, listed or retried.

`outcome` is one of:

| Value | Meaning |
|---|---|
| `task-suggested` | A task was added to the board as `suggested` for the person to accept. |
| `note-filed` | A note was written into the vault. |
| `answered` | It was a question and the answer was shown. (Reserved: nothing sets it until questions are answered from the vault.) |
| `waiting-for-answer` | The classifier wasn't sure (unclear, or below the threshold in 4.3) and a follow-up question is waiting. |
| `skipped` | The person dismissed it, or it was left as it is. |
| `question-open` | It's a question. Answering from the vault isn't built yet, so nothing was filed and it stays open. |

A value that isn't in this list is read as missing. Setting the outcome changes only the frontmatter. Fields that go with an outcome (the list above) are replaced together with it: a new outcome removes the ones it doesn't set. `outcome` is added or replaced, other fields keep their place, and the body stays byte for byte as it was.

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
   - has none of `/ \ : * ? " < > | # ^ [ ]` and no control or invisible formatting characters (right-to-left overrides, zero-width spaces); the characters task titles lose (task format 4.1) are the same;
   - doesn't start or end with whitespace, and doesn't end with `.`;
   - is at most **80** Unicode scalars long.
4. At most **4** folders deep (the file name doesn't count).
5. A file path ends in `.md` (lower case) and has a name before it that doesn't end in whitespace or a dot; a folder path is just folders (no `.md` file).
6. The path as a whole is at most 240 Unicode scalars.
7. **Never in the Tasks folder.** A path in `Notes/Tasks` (or inside it) is refused, whatever the capitals (`notes/tasks` is the same folder on a Mac): every `.md` file there is a task (task format 1), so a note filed there would silently become one. A program whose Tasks folder is somewhere else passes its own folder.

When it's turned into a real location, the result **must** also lie inside the vault after symbolic links are resolved. A link that points at something that doesn't exist yet counts too: writing to it would create the file at its target. A path that fails any check is refused, never "repaired".


## 6. The daily note: "Captured" section

A daily note can list captures under a `## Captured` heading. Adding a line is a pure text transformation: **current note text + line → new note text.**

1. The line is made into one line (as for titles in 4.2). If nothing is left, the text is returned unchanged. It is added exactly as given, so the caller passes a list item such as `- 13:05 call the dentist`; a line that starts with `#` would be a heading and end the section.
2. If the text has a heading line that is exactly `## Captured` (trailing spaces allowed): the line is added at the **end of that section**, after the section's last non-blank line and before the blank lines that separate it from the next heading. The section ends at the next heading of level 1 or 2 (`# ` or `## `) or the end of the text. Headings inside a fenced code block (the CommonMark way: up to 3 spaces, 3 or more backticks or tildes; a closing fence is the same character, at least as long, with nothing after it; ```x``` on one line is inline code, not a fence) or inside frontmatter (up to a line that is exactly `---`) don't count. If there are several, the first one is used.
3. If there is no such heading: a blank line (unless the text is empty or already ends with one), `## Captured`, then the line, are added at the end.
4. The new line is always followed by a line break, and a text that ended without one gets it when the new line goes at the very end. Everything added uses the line break the text already uses (`\n` or `\r\n`; `\n` if it has none).
5. **No other text changes.** Text typed mid-sentence at the end of a note, with no final line break, only gets the line break it was missing.

## 7. The prompt

The prompt that asks the classifier is built from: the capture text, today's date (with weekday), the category ids, a **vault map** (folder tree) and the contents of an optional `_vault-guide.md` in the vault root. All three variable parts have size limits so the prompt stays small and fast:

| Part | Limit |
|---|---|
| Capture text | 4000 characters (the raw file keeps everything) |
| Vault map | 3000 characters, 150 folders, 4 levels deep; hidden folders are left out; a line says how many folders were cut (inside the limit); folders are sorted by lower-case name, the same on every device |
| Vault guide | 4000 characters |

Cut text ends with a marker saying how much was cut. The capture text and the guide are given to the classifier as data between tags, and the prompt says it must not follow instructions found in them. A closing tag typed inside them is defused so it can't end the block early.

For a **follow-up** (10), the prompt also has the question that was asked (limit 300 characters) and the person's answer (limit 1000), as data between `<question>` and `<answer>` tags, with a line telling the classifier to classify the capture again using the answer. Closing tags typed inside are defused like the others. The call is new and stands alone: nothing is remembered from the first one.

The result schema is the JSON schema for the object in 4.1, with `area` limited to the category ids.

## 8. Running the classifier

The classifier is the `claude` command-line tool ([ADR 0015](adr/0015-classify-captures-with-claude-cli.md)). Flags: <https://code.claude.com/docs/en/headless> and <https://code.claude.com/docs/en/cli-reference>.

**The call.** One argument per list entry (no shell, so nothing typed in a capture can add a flag), in this order:

```
-p <prompt> --output-format json --json-schema <schema, one compact line>
--no-session-persistence --tools "" --safe-mode
```

No `--bare` (it skips the subscription login) and no `--model` (the tool's default model). It runs in a new empty folder that is deleted afterwards, with nothing on its standard input, and is stopped after 60 seconds.

**The answer.** The output is one JSON object, or a list of them; then the last entry with `"type": "result"` counts.

| Output | Result |
|---|---|
| Not JSON, cut off, an empty or unrelated list | error: unreadable output (the start of it is shown) |
| `is_error` is true | error: the tool's `result` text (or its `subtype` if there is none) |
| No `structured_output`, or `null` | error: no result |
| `structured_output` fails the checks in 4.2 | error: invalid result, with the reason |
| Otherwise | the `CaptureResult` |

`total_cost_usd`, `usage` and `duration_ms` are read when present, for display only. An exit code other than 0 is an error even if the output looks fine; if the output says why (`is_error`), that message is shown, otherwise the exit code and the start of the error text. A timeout and a missing tool are their own errors.

**Finding the tool.** A Mac app started from the Dock doesn't have a Terminal's PATH, so, in this order: the path in the device settings (`claudePath`); `~/.local/bin/claude`, `~/.claude/local/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`; the answer of `/bin/zsh -lc 'command -v claude'`.

**The schema works with the tool.** Real runs (ADR 0015) accepted it as it is: `enum` lists, `required`, `additionalProperties: false`, and the answer came back in `structured_output`.

## 9. Filing a result

The app applies a result that passes 4.3 (otherwise: 10, waiting). All paths are relative to the vault root, which is the nearest folder above the Tasks folder that has an `.obsidian` folder.

**A task.** A task file with `status: suggested`, the result's `area` and `title` and a `created` time is written through the normal task writer (task format 5.5), so a board watching the Tasks folder shows it. The result's own `status` is not used: the person accepts a suggestion. The `body` becomes the task's notes. A task is never written to a daily note (ADR 0003).

**A note.**
1. The folder is the result's `folder` if it passes the path rules in 5 (including the symbolic link and Tasks-folder rules); otherwise, or if there is none, the Inbox (`Notes/Inbox`), and a `notice` says why. The folder is created if it doesn't exist.
2. The file name is the title made into a name like task titles (task format 4.1) plus `.md`. A name that is taken gets `(2)`, `(3)`… and an existing file is never overwritten (2).
3. The content is frontmatter with `from: '[[Notes/Inbox/<capture file name>]]'` and `created`, then the result's `body` (the typed text if there is none) ending with a line break.

**The daily note line.** After the note is written, one line `- HH:mm [[<note path without .md>]]` (local time) is added under `## Captured` in today's daily note with the function in 6.
- The note is `<folder>/<name>.md`. Folder and name format come from `.obsidian/daily-notes.json` (`folder`, `format`), if the file has them and they are usable (a folder must pass the path rules, a format may use `YYYY YY MM M DD D`, `[text]` and punctuation); otherwise the vault root and `YYYY-MM-DD`.
- The note is **re-read right before writing** and written **atomically** (task format 5.6). A note that doesn't exist is created with just the section, create-only. A note that isn't valid UTF-8 is left untouched.
- If the line can't be added, the note stays filed and a `notice` says so.

**What is recorded.** The outcome and its fields (3) are written into the capture's frontmatter in one atomic write that re-reads the file first. The typed text is never changed.

**A question** (kind `question`, sure enough) gets outcome `question-open`; nothing is filed.

## 10. Order, follow-ups and retry

For every capture, in this order: **(a)** the typed text is saved as a raw file (2); **(b)** the classifier is asked; **(c)** the result is applied (9); **(d)** the outcome is recorded. Nothing happens before (a).

- **One at a time.** Captures are classified one after another in the order they came, never in parallel. A new capture's text is saved at once, even while another is being classified.
- **Not sure** (4.3): outcome `waiting-for-answer` and the question in `follow_up`. Nothing is filed.
- **Follow-up.** The person's answer starts a new call with the original text, the question and the answer (7). Its result is applied like any other, and replaces the old outcome. Another unclear result asks again.
- **Classifier failure** (offline, tool error, timeout): the capture file is left exactly as it is, with no `outcome`. No outcome means "not classified yet".
- **Retry.** A retry takes every capture without an outcome, oldest first (by capture time, then by clash counter), one at a time. A capture that already has an outcome, or that isn't a capture file (3), is skipped.
- A capture whose outcome can't be written (broken frontmatter) is reported; what was already filed stays.

## 11. Undo and skip

- **Skip** sets outcome `skipped` on a capture the app filed nothing for. It is refused for a capture with a filed task or note: use Undo.
- **Undo** takes back what the app made, then sets `skipped` and removes the recorded fields. It only deletes files the app made itself, recorded in the capture, and only if they are still as made:
  - a **suggested task**: its file is deleted if its text still has the recorded SHA-256 (so: still a suggestion, not edited, and not a different task that later got the same name). If not, Undo is refused and nothing changes. A task file that is already gone is fine.
  - a **filed note**: the recorded path must pass the path rules (5) again (the capture file could have been edited). Its text must still have the recorded SHA-256, otherwise Undo is refused and nothing changes (not even the daily note). Then it is deleted, and from the daily note exactly one line equal to the recorded `daily_line` is removed (the last such line), and nothing else. The recorded daily note must be the daily note of the day the capture was made (same folder and name format) and the line must link to the recorded note, otherwise it is left alone: the capture file can be edited by hand. If that line was changed or the note can't be read, the daily note is left as it is and a `notice` says so; the note is still removed.
  - Undo of a capture with nothing filed is Skip.
