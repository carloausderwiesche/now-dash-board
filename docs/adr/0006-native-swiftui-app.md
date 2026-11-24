# 0006. Nowboard moves to a native SwiftUI multiplatform app

- **Date:** 2026-11-24
- **Status:** Accepted

## Context

Nowboard is a Tauri app: a Rust backend (file access, the folder watcher, the quick-add panel) with a React frontend. It works well on the Mac, and learning Rust was part of the point.

Nowboard now needs an iPhone app, and [ADR 0005](0005-icloud-vault-sync.md) moves the vault to iCloud Drive. iCloud makes the whole setup Apple-only, so Tauri's main benefit, one app for every platform, no longer counts for anything. What does count on Apple's platforms: a native feel (animations, drag and drop, haptics), Apple's own iCloud file APIs (file coordination, downloading files that aren't local yet), widgets, and App Intents (Shortcuts, Siri, the Action Button).

## Decision

The end state is **one SwiftUI multiplatform app (iOS and macOS)** in `ios/` in this repo, and it replaces the Tauri app.

- The Xcode project is generated from a text file (XcodeGen `project.yml`), so it stays reviewable. Both targets exist from the start; the iOS one is built first.
- A local Swift package, `NowboardKit`, holds the file format and the store, with no UI and no platform code. The views are shared too; platform code sits behind `#if os(iOS)` / `#if os(macOS)`.
- **We share the file format, not code.** The format is [docs/task-format.md](../task-format.md), and both apps pass the same cases in `fixtures/task-format/`. No Rust in Swift.
- **Order:** the Tauri app stays in daily use until the macOS target reaches parity, measured by a checklist made from `src/` and [DESIGN.md](../../DESIGN.md). Then it's archived, not deleted. Until then the Rust code and its tests are the reference for the format.
- Theme tokens are ported from `src/themes.ts` to Swift. While both apps exist, each has one source of truth for its own platform.

## Alternatives considered

- **Tauri for iOS too:** one codebase, but a web view never feels native: scrolling, drag and drop and haptics are a step behind. iCloud's file APIs, widgets and App Intents need Swift anyway, through a bridge.
- **Keep Tauri on the Mac, SwiftUI only on the iPhone:** two apps, two UIs and two ports of every board rule, forever. Only worth it if Tauri gave the Mac something SwiftUI can't, and it doesn't.
- **A Rust core shared through UniFFI:** the shared part is "read and write markdown files", which is a few hundred lines. Generating bindings, building Rust for every Apple target and debugging across the boundary costs far more than writing it twice against shared fixtures.

## Consequences

- Better iPhone and Mac apps: native gestures, widgets, Siri and Shortcuts, proper iCloud handling.
- **A rewrite.** The UI, the board rules (`src/board.ts`) and the Mac-only parts (global shortcut, the floating quick-add panel, menu bar) all get rebuilt in Swift. Phase 5 is the macOS target and its parity checklist.
- **Learning Rust on this project ends** once the Tauri app is archived; learning Swift starts. Code comments explain Swift in plain language, as they do Rust now.
- Two implementations of the format exist for a while. The fixtures are what keep them in step: a bug found in either app becomes a fixture first.
- Needs Xcode and a paid Apple Developer account to run on a device for more than a week and to use iCloud entitlements.
- We'd revisit this if a non-Apple platform becomes a requirement again (which would also undo ADR 0005).
