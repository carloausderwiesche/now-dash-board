# 0012. The SwiftUI card menu is drawn by the app on the Mac and native on the iPhone

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

The Tauri app draws its own card menu in the theme ([ADR 0004](0004-themed-card-menu.md)). The first SwiftUI version used `.contextMenu`, which is the system menu on both platforms: grey, no category dots, and different from the settings popover next to it. On the iPhone, though, the system long-press menu is what people expect, with its lift, blur and haptics, and a home-made one would feel off.

SwiftUI has no "right-click" gesture on the Mac; `.contextMenu` is the only built-in hook, and it always shows the system menu.

## Decision

- **Mac:** a local `NSEvent` monitor watches right-clicks and control-clicks. Over a Today or Backlog card it opens `CardMenuPopup`, an overlay in the theme with the same rows as the Tauri menu (category dots, Open, Move, Focus, Mark done, Open in Obsidian, Delete file). It opens at the pointer, flips near the window edges, arrow keys move, Esc or a click elsewhere closes, and the page doesn't scroll while it's open.
- **iPhone:** the native `.contextMenu` on long-press stays, with the same actions.
- **Delete file** acts at once in both, with Undo ([ADR 0010](0010-delete-with-undo.md)), so the menu needs no two-click row.

## Alternatives considered

- **System menu on both:** no work, but it doesn't match the theme or show the category dots, which was the reason for ADR 0004.
- **App-drawn menu on the iPhone too:** consistent, but it loses the native lift and haptics and fights the system's long-press.
- **An `NSMenu` with custom views:** still looks like a system menu, and SwiftUI views inside `NSMenuItem` are awkward to theme and size.

## Consequences

- The Mac and Tauri menus look and behave the same; the iPhone feels native.
- The monitor is AppKit code the SwiftUI app has to keep in sync with hover state (which card is under the pointer). It skips the menu while a panel, quick add, settings or a drag is open.
- The two menus share actions but not layout, so a new action has to be added in both `CardMenuPopup` and `CardMenu`.
