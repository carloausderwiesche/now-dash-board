# 0004. Right-click on a card opens a native macOS menu

- **Date:** 2026-11-23
- **Status:** Accepted

## Context

Cards only had a few small buttons. Moving a card, changing its category to a specific one (the dot only cycles through them) or opening it in Obsidian took several clicks or a trip through the detail panel. Right-clicking is where Mac users look for that. In the app, right-clicking currently shows the web view's own menu (Reload, Inspect Element), which makes no sense in a Mac app.

## Decision

Right-clicking a card shows a native menu through Tauri's menu API (`@tauri-apps/api/menu`, allowed by `core:default`). What the menu contains is a pure function, `cardMenu` in `src/cardMenu.ts`, tested with `node:test`. `api.contextMenu` turns it into a native menu. The browser demo has no custom menu and keeps the browser's own.

The menu has no Delete: one slip in a menu would remove a file for good. Deleting stays behind the detail panel's two clicks.

## Alternatives considered

- **An HTML menu drawn by React:** works in the browser demo too and can match the theme. But it would need its own keyboard handling, focus, edge-of-window positioning, submenus and closing rules. It would never feel like a Mac menu, and it's more code to maintain.

## Consequences

- It looks and behaves like every other Mac menu (keyboard, VoiceOver, submenus) with very little code.
- The menu can't be seen or tested in the browser demo. Only `cardMenu` is tested; the native part has to be tried in the app (`npm run app`).
- Only Today and Backlog cards have the menu. Suggested and Done rows keep their buttons.
