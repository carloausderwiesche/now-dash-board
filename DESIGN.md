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
| Today | Big cards tinted with their category colour, in a grid (min 200px). The count sits next to the heading. Empty state: a dashed box saying what's missing and how to fill it ("Nothing planned for today / Drag a card up from Backlog, or press N"). Backlog and Done have the same kind of empty state. While a category is highlighted and a list has none of it, a quiet note at the right of its heading says so. |
| Focus | Optional, at most one card. Hover a Today card → "Focus". The card turns black, doubles in width and shows NOW. "Pause" turns it back. Not a separate column and not a hard limit. |
| Backlog | Smaller plain cards (surface colour, thin border, only a colour dot). Hover → "Today ↑". Kept visually quieter than Today on purpose. |
| Done | At the bottom: a huge number (56px) + "Done today" + "Last: …". Click to expand the list (with Undo). Only today's done tasks are counted. Older ones stay in the vault. |

## Interactions

- **Complete** (round check on a card, or "Mark done" in the panel): the ring fills with the accent (no swelling), the tick draws itself, the title strikes through, then the card glides in one smooth move straight into the Done number (the path is measured), only ever shrinking and fading, no lift or bounce. The Done number gives a small accent-coloured nudge and the remaining cards slide into the gap. About 900ms in total.
- **Drag and drop everywhere**, built on pointer events (not HTML5 drag and drop: in the macOS app that flashes a "+ copy" cursor and leaves stale hover states). A press becomes a drag after 5px of movement, a copy of the card follows the pointer, the cursor stays a closed hand, the page scrolls near the window edges, Esc cancels. (`dragDropEnabled` is also off in `tauri.conf.json`.) Onto Today, Backlog or Done (dropping on Done completes the task). Keep it calm:
  - Picking a card up changes nothing; its own slot is the preview (the card fades).
  - The drop areas follow each other with no gaps: each list's area runs from its cards down to where the next list's cards start, so the space under Today, the Suggested strip and the Backlog heading all count as Today (a short drag up from Backlog is enough). Above the board, the preview stays where it was and dropping there uses that spot.
  - The spot is the grid cell under the pointer: the preview goes exactly into that cell (so it never flips back and forth at row ends), and anything past the last card means "at the end". The double-width focus card is taken into account. The preview only moves after the pointer rests ~70ms on a new spot, but a drop always goes where you let go, even on a quick flick. Other cards slide aside slowly (~400ms, no overshoot).
  - No border: the target section gets a soft tint and a faded "ghost" of the card shows where it lands. While dragging, other cards show no hover styling,.
- **Change category:** click a card's colour dot. It cycles through the categories. Hovering any category dot (header, cards, panel, quick add) shows its name right away; quick add also shows the chosen category's name under its dot.
- **Card buttons** ("Focus ◎", "Pause ‖", "Today ↑") are text plus a small icon, keep the card's text colour on hover (underline only), and hide while you point at the done circle.
- **Filter:** click a colour dot in the header. Other cards fade to 22% opacity instead of disappearing, so you keep the overview.
- **Quick add from anywhere** (⌥ Space): a separate see-through window with only the quick-add box, centred a little above the middle of the screen under the mouse. On macOS it's a non-activating panel, so the board window doesn't come forward. It fades in from slightly smaller (about 250ms, no bounce) and closes on Enter, Esc or a click elsewhere.
- **Quick add** (+ button, `N` in the app, or ⌥ Space as above): a title field, then one row balanced across the width: category dots (⌘1–⌘6, first dot lined up under the title's dot) with the chosen category's name on the left, the Today/Backlog switch (Tab) on the right. The hint line is split the same way. Enter to add, Esc to close. No other fields.
- **Long titles** stop with "…" after 3 lines on Today cards and 2 on Backlog and focus cards. The detail panel always shows the whole title, and hovering a cut-off title for half a second shows it in a tooltip under the card (only when something is actually cut off).
- **Round checks** (cards and checklist) show a faint tick on hover, so it's clear a click finishes it.
- **Detail panel:** click a card's *title*. It slides in from the right as a floating sheet (inset from the window edges, rounded, with a soft shadow). The card stays lifted, as if hovered, while its panel is open. The panel has:
  - a colour strip on top and colour dots to change the category
  - an editable title that grows to fit (never a scrollbar, never cut off)
  - a Today / Backlog switch, the same one as in quick add (a suggested task shows "Accept to Backlog" instead)
  - a checklist using the same round checks as the cards (hover a step for × to remove it)
  - notes
  - the file path (wraps when long), which expands to show the markdown
  - a bin next to ×: one click turns it into "Delete file", a second click deletes the task's .md file for good (it turns back by itself after 4 seconds, or when you click elsewhere)
  - **a sticky footer** with "Mark done" (a solid button; on hover a tick slides in and draws itself) and "Open in Obsidian" (a soft filled button in the theme's well colour, same size and weight, with a ↗ that nudges on hover)

## Settings

A popover under the settings button; clicking anywhere outside (or Esc) closes it.

- **Theme** dropdown (below).
- **Cards:** Roomy / Compact. Compact keeps the same layout with smaller cards, text and gaps, so more fit on screen.
- **Categories:** click a category's dot to open a small floating palette of 14 colours (two even rows of seven) (it sits on top, nothing shifts), rename it inline, reorder it by dragging the ⠿ grip that appears on hover in the left margin (or focus it and press ↑ ↓; the order is the order of the dots everywhere), delete it with the × that appears on hover (at least one stays). Deleting doesn't touch task files; their tasks show in the first category until recategorised. Up to six.
- **Finished tasks are logged in:** the folder (inside the vault) for the daily notes that get a `- [x] Title` line per finished task. "Choose…" opens Finder in the vault; a folder outside the vault is refused. Default `Daily/`.
- **Obsidian vault:** a dropdown of the vaults Obsidian already knows (read from Obsidian's `obsidian.json`) plus "Other folder…", which opens Finder's folder picker. No typing paths.

## Themes

Picked from one dropdown in settings, grouped as:

- **Rams:** Braun (warm off-white, black, Braun orange) and Graphite (its dark version). Small radii (4–8px), hairline borders, Inter.
- **Ive:** Aluminium and Space Grey. Rounder (12–20px), soft shadows, no borders, system font.
- **Pastel:** Peach and Lavender. Soft backgrounds, rounded corners, a pastel accent.
- **Eames:** Plywood (warm ash plywood, walnut-brown text, Eames red-orange), Walnut (its dark version) and Case Study (white panels, near-black text, Eames blue, after the Eames House). Softly rounded (8–16px), Avenir Next.

All theme values live in `src/themes.ts` as CSS variables. Components never hard-code colours. Category colours have a strong value (dots) and a tint (Today cards) for light and dark modes.

## Accessibility rules

- Text contrast is at least 4.5:1 in every theme, including muted text on tinted cards.
- Real `<button>`, `<label>`, `<input>` everywhere. Icon-only buttons have `aria-label`.
- Hover-only actions also appear on keyboard focus (`:focus-within`) and always show on narrow screens.
- Colours that must be told apart (category dots) also have names in tooltips and in the panel.

## Data format (task file format v1, one task = one file)

- One file per task in `<vault>/Notes/Tasks/`, flat (subfolders are ignored).
- **File name = title** + `.md`, e.g. `Fix k6 nightly token.md`. Characters macOS/Obsidian can't take (`/ \ : * ? " < > | # ^ [ ]`) become `-`; at most 80 characters; clashes get ` (2)`, ` (3)`… Editing the title in the app renames the file (when you leave the title field).
- **`title:`** (optional): when the file name can't hold the title exactly (too long, or it had one of those characters), the full title is also stored as `title: …`. It only counts while it still matches the file name, so renaming the file in Obsidian wins. If the file name is the title, the field isn't written.

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
- **Done:** `status: done` + `done:` timestamp, and a `- [x] Title` line in that day's daily note. Undo (or dragging it back out of Done) clears `done:` and takes that line back out of the note (a note left empty is removed). Done files are never deleted automatically; only the bin in the panel deletes a task. The big number counts today; the expanded list shows the last 7 days. Older ones stay on disk.
- **Suggested:** a small strip between Today and Backlog. Accept → top of Backlog (keeps `from:`). Dismiss → the file is deleted.
- **Other writers exist** (MEGA sync, Obsidian, AI agents): the folder is watched and reloaded; unknown frontmatter fields and the body are kept exactly as they are (the body is only rewritten if you edit the checklist or notes in the app); writes go to `.<name>.tmp` and are renamed over the original. A card that someone else marks `status: done` plays the same finish animation (ring → strike → fly → counter bump) and becomes "Last"; the app doesn't rewrite that file or log it to the daily note. A done task whose `done:` has no time (or is empty) is shown with the file's last-saved time, so it sorts as the latest one finished; the file isn't changed.
- A file without frontmatter = backlog, `area: personal`, shown on top. Files starting with `.` and `README.md` are ignored.
- `focus: true` is an extra field of this app (the Focus card).
- **Privacy:** `#private` anywhere in the body shows a small lock on the card. Nothing else changes.
