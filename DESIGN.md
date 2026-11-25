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
| Focus | Optional, at most one card. Hover a Today card → "Focus". The card turns black, doubles in width and shows NOW. "Pause" turns it back. Not a separate column and not a hard limit. In the SwiftUI app the change *grows* (under a second): the card widens on a soft spring with a slight overshoot while the cards around it glide aside, the tint flows into ink, the title grows from 17 to 24pt, it swells a little (×1.035) and settles, the shadow deepens, NOW slides out of the dot a moment later, and the iPhone gives a firm tap. Pause settles back calmly, with no overshoot. |
| Backlog | Smaller plain cards (surface colour, thin border, only a colour dot). Hover → "Today ↑". Kept visually quieter than Today on purpose. |
| Done | At the bottom: a huge number (56px) + "Done today" + "Last: …". Click to expand the list (with Undo). Only today's done tasks are counted. Older ones stay in the vault. |

## Interactions

- **Complete** (round check on a card, "Mark done" in the panel or the card menu, or dropping a card on Done): the ring fills with the accent (no swelling), the tick draws itself, the title strikes through, then the card glides in one smooth move into the Done number (the path is measured), only ever shrinking and fading, no lift or bounce. In the SwiftUI app the path is a gentle curve, down first and then across, like something dropped in; in the Tauri app it's straight. When Done is below the window, the card aims for the bottom edge. The Done number gives a small accent-coloured nudge and the remaining cards slide into the gap. About 900ms in total.
- **Delete** (SwiftUI app; card menu, panel bin, or Dismiss on a suggestion): no "are you sure?". The card shrinks a little, blurs and fades where it stands (about 200ms; it never moves, so it can't be mistaken for finishing), its neighbours close the gap, and an ink pill at the bottom reads "Deleted “…” · Undo" for 5 seconds (⌘Z on the Mac). Undo writes the file back exactly as it was ([ADR 0010](docs/adr/0010-delete-with-undo.md)).
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
- **Right-click a card** for its menu, drawn in the theme like the settings popover: category dots on top (current one ringed, its name on the right), then Open, Move to Today/Backlog, Focus (Today only), Mark done, Open in Obsidian, and Delete file last on its own. Each row has the app's icon on the right, muted until hovered. Delete takes two clicks like the panel's bin: the row turns accent-coloured, reads "Click again to delete", and a thin line drains over 4 seconds before it turns back. Opens at the pointer, flips up or left near the window edges, arrow keys move, Esc or a click elsewhere closes, and the page holds still while it's open ([ADR 0004](docs/adr/0004-themed-card-menu.md)). The SwiftUI app draws the same menu on the Mac, but Delete file acts at once with Undo; on the iPhone a long-press opens the system menu with the same actions ([ADR 0012](docs/adr/0012-swiftui-card-menu.md)).
- **Right-click anywhere else** does nothing, so there's no web-page Reload or Inspect menu. Text fields, the file preview and the query snippet keep the system menu (Copy, Paste, spelling).
- **Nothing on the board is selectable** except text fields, the markdown preview and the error bar, so dragging or double-clicking never highlights dates, headings or titles like a web page would.
- **Round checks** (cards and checklist) show a faint tick on hover, so it's clear a click finishes it.
- **Detail panel:** click a card's *title*. It slides in from the right as a floating sheet (inset from the window edges, rounded, with a soft shadow). The card stays lifted, as if hovered, while its panel is open. The panel has:
  - a colour strip on top and colour dots to change the category
  - an editable title that grows to fit (never a scrollbar, never cut off)
  - a Today / Backlog switch, the same one as in quick add (a suggested task shows "Accept to Backlog" instead)
  - a checklist using the same round checks as the cards (hover a step for × to remove it)
  - notes
  - the file path (wraps when long), which expands to show the markdown
  - a bin next to ×: in the SwiftUI app one click closes the panel and deletes the task (see **Delete**). In the Tauri app one click turns it into "Delete file" and a second click deletes the task's .md file for good (it turns back by itself after 4 seconds, or when you click elsewhere)
  - **a sticky footer** with "Mark done" (a solid button; on hover a tick slides in and draws itself) and "Open in Obsidian" (a soft filled button in the theme's well colour, same size and weight, with a ↗ that nudges on hover)

## Settings

A popover under the settings button; clicking anywhere outside (or Esc) closes it. On the iPhone it's a sheet from below with the same contents.

- **Theme** dropdown (below).
- **Cards:** Roomy / Compact. Compact keeps the same layout with smaller cards, text and gaps, so more fit on screen.
- **Categories:** click a category's dot to open a small floating palette of 14 colours (two even rows of seven) (it sits on top, nothing shifts), rename it inline, reorder it by dragging the ⠿ grip that appears on hover in the left margin (or focus it and press ↑ ↓; the order is the order of the dots everywhere), delete it with the × that appears on hover (at least one stays). Deleting doesn't touch task files; their tasks show in the first category until recategorised. Up to six. In the SwiftUI app the categories are saved in `.nowboard.json` in the Tasks folder, so every device shows the same ones ([ADR 0011](docs/adr/0011-categories-in-the-tasks-folder.md)).
- **Finished tasks in your daily note:** a ready-made Dataview query (with the current tasks folder) and a Copy button. Pasted into the daily-note template, it lists the tasks finished on that note's day. The app itself never writes into daily notes ([ADR 0003](docs/adr/0003-daily-note-query.md)).
- **Obsidian vault:** a dropdown of the vaults Obsidian already knows (read from Obsidian's `obsidian.json`) plus "Other folder…", which opens Finder's folder picker. No typing paths.
- **Tasks folder** (SwiftUI app, instead of the vault, because the iPhone can only open the folder you pick): the folder's path, "Choose…" (the system folder picker) and "Show the demo board". The daily-note query names the folder relative to the vault it's in (the nearest folder above it with `.obsidian`). Categories reorder by dragging the grip, or with VoiceOver's Move up / Move down actions.

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

## Data (one task = one markdown file)

The file format is specified in **[docs/task-format.md](docs/task-format.md)**, with shared test cases in `fixtures/task-format/`. Change the format there, not here. In short: one file per task in `<vault>/Notes/Tasks/`, the file name is the title, the frontmatter holds `status`, `area`, `order`, `created` and `done`, and the body is an optional checklist plus notes.

How the board uses it:

- **Ordering:** moving a card sets its `order` to the midpoint of its two neighbours, so only that file is rewritten. New tasks go on top. Editing the title renames the file (when you leave the title field).
- **Done:** `status: done` + `done:` timestamp, in the task's own file only. Undo (or dragging it back out of Done) clears `done:`. Daily notes show finished tasks through a query (see Settings), so nothing else needs updating. Done files are never deleted automatically; only the bin in the panel or the card menu deletes a task. The big number counts today; the expanded list shows the last 7 days. Older ones stay on disk.
- **Suggested:** a small strip between Today and Backlog. Accept → top of Backlog (keeps `from:`). Dismiss → the file is deleted.
- **Other writers exist** (iCloud sync, Obsidian, AI agents, the iPhone app): the folder is watched and reloaded, and the app only ever changes its own fields. A card that someone else marks `status: done` plays the same finish animation (ring → strike → fly → counter bump) and becomes "Last"; the app doesn't rewrite that file.
- `focus: true` marks the Focus card.
- **Privacy:** `#private` anywhere in the body shows a small lock on the card. Nothing else changes.
