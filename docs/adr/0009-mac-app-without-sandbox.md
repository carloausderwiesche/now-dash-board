# 0009. The Mac app runs without the App Sandbox, for now

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

The SwiftUI Mac app ([ADR 0006](0006-native-swiftui-app.md)) started out sandboxed. A sandboxed app may only open folders you picked, and it remembers them with a *security-scoped bookmark*. That bookmark is tied to the app's code signature. Without a paid developer account, every build is signed ad hoc with a new signature, so after each rebuild the app silently lost the Tasks folder and showed the demo board ("there is no Open in Obsidian").

It also needed a sandbox exception to read the Tauri app's `settings.json`.

## Decision

The macOS build runs **without the App Sandbox** (`com.apple.security.app-sandbox: false` in `apple/project.yml`), like the Tauri app. The folder is remembered with a plain bookmark, which survives rebuilds. iOS isn't affected: it always sandboxes, and access to a folder picked in Files comes with the bookmark.

## Alternatives considered

- **Keep the sandbox and sign with a development certificate:** a stable signature keeps the bookmarks valid. But it needs an Apple developer team set up in Xcode, and the free tier's certificates expire. Worth revisiting once there's a paid account.
- **Keep the sandbox and ask for the folder after every rebuild:** fine for users of a released app, annoying while developing every day.

## Consequences

- The folder stays picked across rebuilds. Reading the Tauri settings needs no exception.
- The app could read any file the user can. It only reads and writes the Tasks folder and the Tauri settings file, the same as the Tauri app.
- The Mac App Store requires the sandbox. If Nowboard goes there, turn it back on and use security-scoped bookmarks with a stable signature.
- If the saved folder can't be found, the board says so ("Choose it again") instead of falling back to the demo without a word.
