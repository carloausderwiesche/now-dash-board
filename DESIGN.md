# Nowboard — design decisions

Read this before changing how something looks or behaves. These decisions came out of several rounds of design review; each one has a reason.

## Principles

1. **Clarity at a glance.** The board answers one question: *what am I doing today?* Anything that doesn't help answer it goes, or moves behind a click.
2. **No clutter.** No helper sentences ("one thing at a time…"), no counters like "3 open", no shortcut footer. Shortcuts live in tooltips and the quick-add hint line.
3. **One column, top to bottom:** Today → Backlog → Done. No swimlanes and no side columns. A previous version had topic rows; they tripled the height and were the main source of clutter.
4. **Throw cards, don't schedule them.** Today is a pile of cards you'll get to at some point. No times, no estimates, no day timeline. A tried-and-rejected version had a day ruler; it felt like planning work, not doing it.
5. **Colour is the category.** Personal, Work and Freelance are colours, not rows or tags. Colour is used *only* for categories, plus one accent colour for actions and focus. Everything else is neutral.
6. **Large, confident typography.** A big date number, bold section headings with their count next to them, and a thick 2px rule under each heading. Swiss/editorial, not app-generic.
7. **Satisfying, short animations.** Every completion should feel good, last under a second, and show where the task went.

## Layout

| Area | Decision |
|---|---|
| Window | Desktop app has no title bar: the content runs to the top edge, the window buttons float over it, and the top strip / empty header space drags the window. |
| Header | Big day number (96px), weekday and month stacked beside it. Right side: category dots (filter), settings button, round black + button. Nothing else. |
| Today | Big cards tinted with their category colour, in a grid (min 200px). The count sits next to the heading. Empty state: dashed box saying "Throw cards here". |
| Focus | Optional, at most one card. Hover a Today card → "Focus". The card turns black, doubles in width and shows NOW. "Pause" turns it back. Not a separate column and not a hard limit. |
| Backlog | Smaller plain cards (surface colour, thin border, only a colour dot). Hover → "Today ↑". Kept visually quieter than Today on purpose. |
| Done | At the bottom: a huge number (56px) + "Done today" + "Last: …". Click to expand the list (with Undo). Only today's done tasks are counted. Older ones stay in the vault. |

## Interactions

- **Complete** (round check on a card, or "Mark done" in the panel): the ring fills with the accent, the tick draws itself, the title strikes through, then the card lifts slightly and glides straight into the Done number (the path is measured, not a fixed "fall"), shrinking and fading as it arrives. The Done number bumps in the accent colour and the remaining cards slide into the gap. About 900ms in total.
- **Drag and drop everywhere.** Onto Today, Backlog or Done (dropping on Done completes the task). Onto another card to place it *before* that card. No borders while dragging: the target section gets a soft background tint, and a faded copy of the card (a "ghost") appears exactly where it will land. Keep it calm: the dragged card's own slot *is* the preview until you point somewhere else, so a small nudge moves nothing; then only the cards in between shift by one place, slowly (~400ms, no overshoot). The left half of a card means "before it", the right half "after it", so both sides of a gap point at the same spot and the preview never flickers.
- **Change category:** click a card's colour dot. It cycles through the categories.
- **Filter:** click a colour dot in the header. Other cards fade to 22% opacity instead of disappearing, so you keep the overview.
- **Quick add** (+ button, `N` in the app, ⌥ Space from anywhere): a title field, colour dots (⌘1–⌘6), a Today/Backlog switch (Tab), Enter to add, Esc to close. No other fields.
- **Detail panel:** click a card's *title*. It slides in from the right with:
  - a colour strip on top and colour dots to change the category
  - an editable title
  - one quiet line: "In Today · Move to Backlog" (an action, not two views of the card)
  - a checklist using the same round checks as the cards
  - notes
  - the file path, which expands to show the markdown
  - **a sticky footer** with "Mark done" (a solid button with text only, no icon) and "Open in Obsidian"

## Settings

A popover under the settings button; clicking anywhere outside (or Esc) closes it.

- **Theme** dropdown (below).
- **Categories:** click a category's dot to open its colour swatches, rename it inline, delete it with the × that appears on hover (at least one stays). Deleting doesn't touch task files; their tasks show in the first category until recategorised. Up to six.
- **Obsidian vault:** a dropdown of the vaults Obsidian already knows (read from Obsidian's `obsidian.json`) plus "Other folder…", which opens Finder's folder picker. No typing paths.

## Themes

Picked from one dropdown in settings, grouped as:

- **Rams:** Braun (warm off-white, black, Braun orange) and Graphite (its dark version). Small radii (4–8px), hairline borders, Inter.
- **Ive:** Aluminium and Space Grey. Rounder (12–20px), soft shadows, no borders, system font.
- **Pastel:** Peach, Mint and Lavender. Soft backgrounds, rounded corners, a pastel accent.

All theme values live in `src/themes.ts` as CSS variables. Components never hard-code colours. Category colours have a strong value (dots) and a tint (Today cards) for light and dark modes.

## Accessibility rules

- Text contrast is at least 4.5:1 in every theme, including muted text on tinted cards.
- Real `<button>`, `<label>`, `<input>` everywhere. Icon-only buttons have `aria-label`.
- Hover-only actions also appear on keyboard focus (`:focus-within`) and always show on narrow screens.
- Colours that must be told apart (category dots) also have names in tooltips and in the panel.

## Data format (task file format v1, one task = one file)

- One file per task in `<vault>/Notes/Tasks/`, flat (subfolders are ignored).
- **File name = title** + `.md`, e.g. `Fix k6 nightly token.md`. Characters macOS/Obsidian can't take (`/ \ : * ? " < > | # ^ [ ]`) become `-`; at most 80 characters; clashes get ` (2)`, ` (3)`… Editing the title in the app renames the file (when you leave the title field).

```markdown
---
status: today          # today | backlog | done | suggested
area: work             # category id (= card colour)
order: 1024.5          # position within its status; float, smaller = higher
created: 2026-11-22T09:40
done:                  # timestamp, set when done; cleared if reopened
project:               # optional, e.g. "[[Wiki/Projects/uKonn-X]]"
from:                  # only on agent-suggested tasks, e.g. "[[Notes/2026-11-22]]"
---
- [ ] optional checklist item
- [x] another one
Free text notes below the checklist are allowed.
```

- The body is optional. Lines starting with `- [ ]` / `- [x]` are the checklist; the rest is notes.
- **Ordering:** moving a card sets its `order` to the midpoint of its two neighbours, so only that file is rewritten. New tasks go on top (smallest order − 1024).
- **Done:** `status: done` + `done:` timestamp. Files are never deleted. The big number counts today; the expanded list shows the last 7 days. Older ones stay on disk.
- **Suggested:** a small strip between Today and Backlog. Accept → top of Backlog (keeps `from:`). Dismiss → the file is deleted.
- **Other writers exist** (MEGA sync, Obsidian, AI agents): the folder is watched and reloaded; unknown frontmatter fields and the body are kept exactly as they are (the body is only rewritten if you edit the checklist or notes in the app); writes go to `.<name>.tmp` and are renamed over the original.
- A file without frontmatter = backlog, `area: personal`, shown on top. Files starting with `.` and `README.md` are ignored.
- `focus: true` is an extra field of this app (the Focus card).
- **Privacy:** `#private` anywhere in the body shows a small lock on the card. Nothing else changes.
