# 0010. The SwiftUI app deletes at once and offers Undo, instead of asking first

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

In the Tauri app, deleting takes two clicks: the card menu's row or the panel's bin turns accent-coloured and needs a second click within 4 seconds ([ADR 0004](0004-themed-card-menu.md)). The first SwiftUI version asked with a system confirmation dialog instead, which on the Mac drops a sheet from the top of the window. It felt out of place for something this small, and the iPhone's long-press menu can't confirm in place at all.

Deleting a task is still serious: the `.md` file is gone, and nothing else keeps a copy.

## Decision

In the SwiftUI app, Delete (card menu, panel bin) and Dismiss (suggestions) act at once. The card shrinks, blurs and fades where it stands, and an ink pill at the bottom reads "Deleted “…” · Undo" for 5 seconds (⌘Z on the Mac). The app keeps the file's text in memory, so Undo writes the file back byte for byte (`TaskFolder.restore`). If the name was taken in the meantime, it gets a free one.

## Alternatives considered

- **Two clicks in place, like the Tauri app:** safe, but slower every time, and it needs a menu drawn by the app on the iPhone too.
- **A confirmation dialog:** one more window for one more click; the reason ADR 0004 didn't use one either.
- **Moving the file to the Trash:** it behaves differently on iOS and in iCloud Drive, and the app would still need its own Undo to take a file back out.

## Consequences

- Deleting is one click, and a slip costs one more click to undo, not a lost file.
- Only the last delete can be undone, and only while the app is open. After 5 seconds the text is dropped.
- A file that couldn't be read before deleting (rare) comes back rebuilt from its fields, not byte for byte.
- The Tauri app (bug fixes only, [ADR 0006](0006-native-swiftui-app.md)) keeps its two clicks until it's archived.
