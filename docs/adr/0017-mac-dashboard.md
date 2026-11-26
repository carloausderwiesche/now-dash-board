# 0017. The Mac app opens a Dashboard that drops the board's one-column rules

- **Date:** 2026-11-26
- **Status:** Proposed

## Context

The board answers one question, *what am I doing today?*, in one column with nothing else on it ([DESIGN.md](../../DESIGN.md), principles 2 and 3). Captures ([the capture format](../capture-format.md)) add a second job: you throw a thought at the app, the app sorts it, and sometimes it asks you something. That needs a place to type that is always there, a place to see what happened to what you typed, and room for later additions (calendar, chat, a focus timer) that the board has no room for.

## Decision

On macOS the app opens a **Dashboard** window ([DESIGN.md, "Dashboard"](../../DESIGN.md)): a header with the day, a switch between three pages (Dashboard, Tasks, Inbox), and a capture bar pinned to the bottom of every page. The Tasks page is the existing board, unchanged. The iPhone app keeps the board as its one screen, and the Tauri app is not touched.

This drops the one-column rule (principle 3) and bends the no-clutter rule (principle 2) **for the Mac Dashboard only**, on purpose, with these limits kept: the themes' colours, fonts and radii only, colour means category, short animations, and nothing that isn't built yet: no placeholder boxes. The right-hand column of the Dashboard page appears only once a box is registered.

Implementation choices:
- The board is reused as it is (`BoardView(embedded:)` hides its own header and chrome), so nothing about dragging, the card menu or the panel is rewritten. The panels, menus and settings popover are drawn once, by the dashboard around all three pages.
- What the capture bar's strip shows, and how the Inbox list is ordered and worded, are pure functions in NowboardKit (`CaptureStrip.decide`, `InboxList`, `InboxText`) with tests, like the board rules.
- Captures are only made for a real Tasks folder inside an Obsidian vault. On the demo board the bar is shown but switched off, with the reason.

## Alternatives considered

- **Keep the board and add a capture field to its header:** no new pages, but the Inbox (where "what happened to what I typed" lives) and the questions would have nowhere to be, and the header would gain clutter on every screen.
- **A separate capture window or panel (like the ⌥ Space quick add):** it would not show the answer or the question next to the work, and a panel that disappears can't hold a question until you have time for it.
- **Rewrite the board as three columns (Today, Suggested, Backlog) now:** it matches the design sketch, but touches drag and drop and the card flights, the most fragile code in the app, for no new function. It can come later on top of this shell.

## Consequences

- The Mac and the iPhone now look different on purpose: the Mac has pages, the iPhone has the board. The DESIGN.md principles are true for the board and the iPhone; the Dashboard section says where the Mac differs.
- The `N` key for quick add (the board header's + button) doesn't exist on the Dashboard; ⌥ Space and the capture bar replace it. The Tauri app uses ⌥ Space too, so only one of the two apps should be running.
- More surface to keep consistent with [DESIGN.md](../../DESIGN.md) and the iPhone app; later packages (calendar, chat, focus sessions) plug into the registered boxes and the capture bar rather than adding screens.
- Revisit when a second box exists (to see whether the right column works), and when the Tasks page gets its three-column version.
