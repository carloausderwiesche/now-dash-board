# 0004. Right-click on a card opens a menu drawn by the app

- **Date:** 2026-11-23
- **Status:** Accepted (in the SwiftUI app, Delete's two clicks are superseded by [0010](0010-delete-with-undo.md))

## Context

Cards only had a few small buttons. Moving a card, picking a specific category (the card's dot only cycles through them), opening it in Obsidian or deleting it took several clicks or a trip through the detail panel. Right-clicking is where Mac users look for that.

Everywhere else, right-clicking showed the web view's own menu (Reload, and Inspect Element in development). That gives away that the app is a web page, and Reload can throw away what you were doing.

## Decision

- **Cards** open a menu drawn by the app (`components/CardMenu.tsx`), styled with the theme: category dots on top, then Open, Move, Focus, Mark done, Open in Obsidian, and Delete last on its own.
- **Delete takes two clicks**, like the bin in the detail panel: the row turns accent-coloured and reads "Click again to delete" for 4 seconds, then turns back by itself.
- **What the menu contains and where it opens** are pure functions (`cardMenu`, `placeMenu` in `cardMenu.ts`), tested with `node:test`.
- **Everywhere else** no menu opens, except in text you can select (fields, the file preview, the query snippet, the error bar), which keep the system menu for Copy, Paste and spelling. One `contextmenu` listener in `main.tsx` does this for both windows.

## Alternatives considered

- **The native macOS menu** (`@tauri-apps/api/menu`), the first version of this. Less code, and keyboard, VoiceOver and edge handling come for free. But a native menu can't confirm in place (an item click always closes it), so Delete would have needed a separate dialog. It also can't show the category dots or follow the theme, and it doesn't exist in the browser demo.
- **A confirm dialog for Delete:** one more window for one more click, and a different pattern from the detail panel's bin.

## Consequences

- The menu matches the board in every theme, and the browser demo has it too.
- The app now does what a native menu would: placing it at the pointer and flipping it near the edges, arrow keys, Enter, Esc and Tab, closing on a click elsewhere or when the window loses focus, and holding the page still while it's open. That's more code to maintain than the native menu.
- Delete is one right-click away. The two clicks, the 4-second timeout and its place at the bottom are what keep that safe.
- Only Today and Backlog cards have the menu. Suggested and Done rows keep their buttons.
