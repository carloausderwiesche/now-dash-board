# 0003. Daily notes list finished tasks with a query; the app doesn't write them

- **Date:** 2026-11-23
- **Status:** Accepted

## Context

Finishing a task appended `- [x] Title` to that day's daily note, and Undo took the line out again by rewriting the whole note. Daily notes are files Nestor edits often, usually with Obsidian open on them. That caused:

- **Glued lines.** The append didn't check whether the note ended with a line break. While you're typing on the last line it doesn't, so the log ended up in the middle of your sentence (`half a thought- [x] Buy milk`).
- **Edit conflicts.** Any outside write to an open note makes Obsidian merge it into the editor. Undo's full rewrite could overwrite what you'd just typed.

Moving the lines under a `## Done` heading would fix the gluing, but not the conflicts: it's still an outside write into a note you're editing.

## Decision

The app only writes task files. Each task already stores when it was finished (`done: 2026-11-23T10:40`), so a daily note can *ask* for that day's tasks instead of being written to. Settings shows a ready-made Dataview query, with a Copy button, for the daily-note template:

````markdown
```dataview
LIST FROM "Notes/Tasks"
WHERE status = "done" AND dateformat(default(done, file.mtime), "yyyy-MM-dd") = this.file.name
SORT default(done, file.mtime) ASC
```
````

A done task without a `done:` date (set by hand in Obsidian) counts on the day its file was last saved: `default(done, file.mtime)` mirrors the app's own fallback (`done_time` in `src-tauri/src/tasks.rs`), so the daily note and the board show the same tasks.

The `dailyFolder` setting, `log_to_daily_note` and `unlog_from_daily_note` are gone.

## Alternatives considered

- **Append safely, under a `## Done` heading:** fixes the gluing but keeps the edit conflicts and the Undo rewrite.
- **Obsidian Bases** (built in, no plugin): the same idea without Dataview. Not chosen for now because the filter for "done on this note's day" depends on how Obsidian types the `done` property, which hasn't been checked in the real vault yet. Worth switching to once it's tried.

## Consequences

- The app never touches a note you're editing. Undo needs no special handling, and two functions plus their test are deleted.
- Needs the Dataview plugin, and the query in the daily-note template (or pasted into existing notes).
- The list is live, not text: it changes if a task is renamed, reopened or deleted. A task finished on Monday and reopened on Tuesday disappears from Monday's list.
- Lines logged before this change stay in old daily notes. Undo no longer removes them.
- The query assumes daily notes are named `YYYY-MM-DD` (Obsidian's default).
