# Task file format, v1

This is the one place that says what a Nowboard task file is. Every program that reads or writes the Tasks folder has to follow it: the Mac app (`src-tauri/src/tasks.rs`), the iPhone app (`ios/`, planned) and anything written by hand, a Shortcut or an AI agent.

The rules are checked by the conformance cases in [`fixtures/task-format/`](../fixtures/task-format/README.md). If you change a rule here, change the fixtures and the code in the same PR, and add an ADR (it's a file-format change).

The words **must**, **must not** and **should** are used in their usual spec sense.

## 1. The folder

- Tasks live in one folder, by default `<vault>/Notes/Tasks/`. One task = one file.
- The folder is **flat**: only files directly inside it are tasks. Subfolders and the files in them are ignored.
- A file is a task only if its name:
  - ends with `.md` (lower case; `Note.MD` is ignored),
  - doesn't start with `.` (hidden files, our own `.Name.md.tmp` files and iCloud's old `.Name.md.icloud` placeholders),
  - isn't `README.md` (in any capitalisation).
- Files are UTF-8. A file that can't be read as UTF-8 is skipped, not an error.
- Other programs write to this folder too (Obsidian, sync, agents). A reader must expect files to appear, change, be renamed and disappear at any time.

## 2. Anatomy of a file

```markdown
---
status: today
area: work
order: 1024.5
created: 2026-11-22T09:40
done:
project: '[[Wiki/Projects/uKonn-X]]'
from: '[[Notes/2026-11-22]]'
---
- [ ] optional checklist item
- [x] another one
Free text notes below the checklist are allowed.
```

### 2.1 Splitting frontmatter and body

1. A leading byte-order mark (U+FEFF) is ignored.
2. The file has frontmatter only if it **starts** with `---` followed by a line break (`\n` or `\r\n`).
3. The frontmatter ends at the first following line that **starts with** `---`. The text between the two lines is the YAML.
4. After that closing `---`, one line break (`\r\n` or `\n`) is skipped if present; everything after it is the **body**.
5. No opening `---`, or no closing line: the file has no frontmatter and the whole text is the body.

### 2.2 Reading the YAML

- Empty YAML (or only whitespace, or `null`) = no fields.
- YAML that is invalid, or isn't a list of `key: value` fields (for example a plain list): treat the file as having **no fields**. The task still shows up. The body is still the text after the closing `---`. (Saving such a file is refused; see 5.1.)
- Reading a field "as text":
  - missing, `null`, or a string that is empty or only whitespace → **missing**
  - a string → that string, unchanged
  - a boolean or number → its usual text form (`true`, `1024`, `10.5`)
  - a list or map → not defined. Writers **must** quote wiki links (`project: '[[Wiki/X]]'`), because unquoted `[[Wiki/X]]` is a nested list in YAML.

## 3. Fields

| Field | Meaning | When missing or not understood |
|---|---|---|
| `status` | Which list: exactly `today`, `backlog`, `done` or `suggested` (lower case, a string). | `backlog`. So do `Today`, `someday`, `3`. |
| `area` | Category id, which is the card colour (`work`, `personal`, …). Read as text. | The old field `colour`, read as text; if that's missing too, `personal`. An id that's not in the categories shows in the first category (a UI rule, nothing is written). |
| `order` | Position within its list. A YAML number, integer or decimal. Smaller = higher. | **Missing** (see 4.2). A string like `"5"` is not a number. |
| `created` | When the task was made, `YYYY-MM-DDTHH:MM`, local time. Read as text. | Missing. |
| `done` | When it was finished, `YYYY-MM-DDTHH:MM`, local time. Read as text. Empty unless `status: done`. | Missing (see 4.3 for done tasks). |
| `project` | Optional link, for example `'[[Wiki/Projects/uKonn-X]]'`. Read as text. | Missing. |
| `from` | Only on suggested tasks: where the suggestion came from, for example `'[[Notes/2026-11-22]]'`. Read as text. | Missing. |
| `focus` | `true` on the one card you're working on. Only the YAML boolean `true` counts. | Off. So is `"true"` in quotes, `yes` or `1`. |
| `title` | The full title, only when the file name can't hold it (see 4.1). | The title is the file name. |
| anything else | Not ours. | Kept as it is (see 5.1). |

Timestamps have no seconds and no time zone: `2026-11-22T09:40` is the local wall-clock time of the device that wrote it.

### 3.1 The body

- The body is split into lines (`\n` or `\r\n`).
- A line is a **checklist item** if, after removing leading whitespace, it starts with:
  - `- [ ] ` (dash, space, `[`, space, `]`, space) → an open item; its text is the rest of the line
  - `- [x] ` or `- [X] ` → a done item
  
  `- [ ]` without a space and text after it isn't an item. Indented items count as items (nesting is flattened).
- All other lines are **notes**: they're joined with `\n` in their original order, and the result is trimmed of whitespace at both ends.
- **Private:** if the body contains `#private` (exactly, case-sensitive) anywhere, the card shows a lock. Nothing else changes.

## 4. Derived values

These are values a reader works out. They're shown, but **never written back** just because a file was read.

### 4.1 Title and file name

The title is the file name without `.md` (the **stem**), unless the file has a `title:` field that **belongs to it**.

A `title:` belongs to the file when `stem_for(title)` (below) equals the file's stem, or equals the stem with a clash counter removed. A clash counter is a final ` (n)`, where `n` is one or more digits: `Fix- token (2)` → `Fix- token`. A `title:` that doesn't belong (the file was renamed in Obsidian) is ignored, so the file name wins.

`stem_for(title)` turns a title into a file stem:

1. Replace each of these characters, and each control character, with `-`:
   `/ \ : * ? " < > | # ^ [ ]`
2. Trim whitespace at both ends.
3. Keep the first **80 characters**. A character here is a **Unicode scalar value** (a Rust `char`, a Swift `UnicodeScalar`), not a byte and not a Swift `Character`.
4. Trim dots and whitespace at both ends (a leading dot would hide the file).
5. If nothing is left, use `Untitled`.

Examples: `Fix k6: nightly/token?` → `Fix k6- nightly-token-`; `[[link]] #tag ^block` → `--link-- -tag -block`; `  .hidden  ` → `hidden`; empty → `Untitled`. More are in `fixtures/task-format/file-names.json`.

### 4.2 Missing order

All tasks without an `order` go **on top**: they get the smallest `order` of all loaded tasks (in any list) minus 1024, or `0` if no task has one. They all get the same value, so among themselves they sort by title. This isn't written to the file; it only lasts until the card is moved.

### 4.3 Done time

For a task with `status: done`:

- no `done:` → use the time the file was last modified, as `YYYY-MM-DDTHH:MM` local time;
- `done:` is a bare date (exactly 10 characters, `YYYY-MM-DD`) and the file was last modified that same day → use the modified time instead;
- otherwise keep `done:` as it is.

This makes a task finished by hand in Obsidian sort as the latest one, and count on the right day. The file isn't changed.

### 4.4 Sorting and moving

- A list is sorted by `order` (smaller first), then by title.
- New tasks go on top of their list: the list's smallest `order` minus 1024, or `0` for an empty list.
- Moving a card sets its `order` to the **midpoint** of its new neighbours, so only that one file is rewritten. At the top: the next card's order minus 1024; at the end: the previous card's order plus 1024; alone: `0`.
- If two neighbours share the same order (there's no number between them), the whole list is renumbered once as 1024, 2048, 3072…
- Moving out of `done` clears `done:`. Moving out of `today` turns `focus` off.

The reference implementation is `planMove` in `src/board.ts`.

## 5. Writing

### 5.1 Saving an existing task

1. **Re-read the file from disk right before writing.** Another program may have changed it since it was loaded.
2. If its frontmatter isn't valid YAML, or isn't a list of fields, **refuse** to save and tell the user to fix it in Obsidian. Never overwrite it.
3. Set only the fields this app owns. A field that's already there keeps its position; a new one is added at the end:
   - `status`: always.
   - `area`: always. `colour` is removed (it's the old name).
   - `order`: the order the task has, including a derived one (4.2). So saving a file that had no `order` writes the order it was shown with.
   - `created`: only if known.
   - `done`: always, empty (`done:`) unless finished.
   - `focus: true` only while focused; otherwise the field is removed.
   - `title`: see 5.3.
4. **Keep every other field** (`project`, `from`, `agent_note`, anything) with the same key, value and position.
5. **Keep the body byte-for-byte**, unless the checklist or notes actually changed: parse the old body (3.1), compare items and trimmed notes with the new ones, and only if they differ write a new body (5.4).
6. Write the file as `---\n` + YAML + `---\n` + body, using an **atomic write** (5.6).

What "keep" means for the YAML: the same keys, in the same order, with the same values. How values are quoted may change (`"[[X]]"` can come back as `'[[X]]'`), and YAML comments inside the frontmatter aren't kept. A BOM and `\r\n` line breaks in the frontmatter are not kept either; the body keeps whatever it had.

### 5.2 Writing the YAML

- One `key: value` per line, each ending in `\n`.
- A missing value is written as a bare `key:` (nothing after the colon).
- Strings are quoted whenever YAML would otherwise read them as something else (`'[[Wiki/X]]'`, `'Fix: token'`). Timestamps like `2026-11-22T09:40` and plain words are written without quotes.
- A whole-number `order` is written without `.0` (`-1024`, not `-1024.0`). Other orders are written as decimals (`1024.5`).

### 5.3 The `title:` field

- If the file stem is the title (with or without a clash counter), `title:` isn't needed: a `title:` that belongs to the file (4.1) is removed. A `title:` that doesn't belong is left alone, like any unknown field.
- Otherwise (the title was too long, or had one of the replaced characters), write the full title as `title:`.

### 5.4 Writing a body

When the checklist or notes changed:

1. Each item as a line: `- [ ] text\n` or `- [x] text\n` (always a lower-case `x`).
2. If there are notes (after trimming): a blank line (only if there were items), then the trimmed notes, then `\n`.

No items and no notes → an empty body.

### 5.5 New tasks

- The file name is `stem_for(title)` + `.md`. If that name is taken (or would be ignored), try `stem (2).md`, `stem (3).md` and so on.
- Fields, in this order: `status`, `area`, `order`, `created` (written as bare `created:` if unknown), `done`, `focus` (only if true), `project` (bare `project:` if none), then `title` if needed (5.3).
- A file written by hand or by a Shortcut may leave out any field. The minimum useful file is `status`, `area` and `created`; with no `order` it goes on top (4.2).

### 5.6 Atomic writes

Write the whole new content to `.<name>.tmp` in the same folder (for example `.Buy milk.md.tmp`), then rename it over `<name>`. If the rename fails, delete the temporary file. Nobody ever reads a half-written task. (The leading dot means readers ignore the temporary file.)

### 5.7 Renaming

Editing the title renames the file:

1. Pick a free name for the new title as in 5.5. The task's own current file doesn't count as taken, compared without regard to capitals (macOS treats `Fix.md` and `fix.md` as the same file), so a change of capitals only is a plain rename.
2. Rename the file (unless the name didn't change).
3. Fix `title:`: remove it if it belonged to the **old** name, then apply 5.3 for the new name. Only write the file (atomically) if this changed something. If the frontmatter is invalid YAML, leave the content alone.

### 5.8 Completing, reopening, deleting

- **Complete:** `status: done`, `done:` = now, `focus` removed. Only the task's own file is written, never a daily note ([ADR 0003](adr/0003-daily-note-query.md)).
- **Reopen** (Undo, or moving it out of Done): the new status, `done:` cleared.
- **Delete:** remove the file. Only an explicit user action deletes a task (the bin in the panel, the card menu, or dismissing a suggestion).

### 5.9 Safety

A task id is a file name. Implementations **must** refuse any id that isn't a single plain file name directly inside the Tasks folder, or that would be ignored (1): `../x.md`, `/etc/x.md`, `sub/x.md`, `.x.md`, `README.md`.

## 6. Conflict copies

Sync services can leave copies like `Buy milk 2.md` or `Buy milk (conflicted copy).md`. They're ordinary tasks under this spec. Readers must not delete them automatically.
