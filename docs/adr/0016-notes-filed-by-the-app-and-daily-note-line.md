# 0016. Notes are filed by the app and appended to the daily note

- **Date:** 2026-11-26
- **Status:** Proposed

## Context

[ADR 0003](0003-daily-note-query.md) decided that the app doesn't write daily notes: finishing a task used to append a line to the daily note, which glued lines onto half-typed sentences and could overwrite what you were typing in Obsidian. A query in the daily note lists finished tasks instead.

Captures (see [the capture format](../capture-format.md)) change two things. A capture that is a note has to be written as a new file somewhere in the vault, and the person wants to see in the daily note what was captured that day, with a link to it. A link back from the daily note is what makes a filed note findable; a query can't list notes the way it lists tasks, because they carry no status.

## Decision

The app files a classified note as a new Markdown file and appends **one line** to today's daily note, `- 13:05 [[Wiki/Ideas/Note title]]`, under a heading of its own, `## Captured`. This partly supersedes ADR 0003, for captured notes only. **What stays true from ADR 0003:** the app never writes finished tasks into daily notes, and a suggested task is written to the Tasks folder only.

The risk is the one ADR 0003 found: an outside write to a note that is open in Obsidian can conflict with what the person is typing. The owner accepted it for captures. What limits it:
- The note is **re-read right before** the append and written **atomically** (temporary file, then rename), so what Obsidian saved a moment ago is kept.
- The append is a pure text function that adds a line break first if the note ended without one, then writes under its **own heading**, and changes no other text (tested with CRLF, no final line break and text typed mid-sentence).
- **Undo removes only its own line**, and only if the line is still there exactly as written. The recorded line is kept in the capture file.
- A daily note that isn't valid UTF-8 is never written; the note stays filed and the person is told.
- A missing daily note is created create-only, with just that section.
- The daily note's folder and name format are read from Obsidian's `.obsidian/daily-notes.json`, so the line lands in the note Obsidian itself uses.

Other decisions that go with it:
- **Where a note goes** is the model's suggestion, but only if it passes the path rules (relative, no `..`, no hidden folders, at most four deep, not the Tasks folder, no symbolic link out of the vault). Anything else falls back to `Notes/Inbox` with a notice. A model can be tricked by the text it reads, so its path is never trusted.
- **The app creates, never overwrites.** A name clash gets `(2)`.
- **Undo deletes files**, but only files the app made and recorded, and only if unchanged since (a suggested task still `suggested`, a note with the same SHA-256). A file the person has edited or accepted is theirs and is left alone.
- **The link uses the full path** (`[[Wiki/Ideas/Title]]`), so two notes with the same name in different folders can't be confused; the cost is a longer line.
- **Questions** (kind `question`) are not answered yet: they get outcome `question-open` and nothing is filed. Answering from the vault is a later package.
- **A suggested task has no `from:` link** back to the capture, because the task format doesn't write `from` for new tasks. The capture records which task it made.

## Alternatives considered

- **Append nothing to the daily note; list captures with a query:** no write conflict, but a note has no status to query by, so the daily note could only list "everything in the Inbox", which stops being true once notes are filed elsewhere.
- **Write the daily note line first, or without a heading of our own:** a heading of our own is what lets us find the place to add, and add nothing else.
- **Keep an append log in the app's own file:** safe from conflicts, but invisible in Obsidian, which is where the person reads their day.

## Consequences

- The daily note can show captures and the person can follow a link to each. The risk of an edit conflict with a note open in Obsidian is accepted and limited as above, not removed.
- If someone edits the `## Captured` section by hand, Undo may not be able to remove the line; it then says so and leaves it.
- Re-reading before the write narrows but doesn't close the window between read and rename. If this turns out to bite, writing the line through Obsidian itself (a plugin or the URI scheme) would be the next step.
- Revisit if captures should be listed some other way than by a line in the daily note.
