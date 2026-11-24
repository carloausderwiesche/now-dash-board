# 0008. The Swift app lives in this repo, in `apple/`

- **Date:** 2026-11-24
- **Status:** Accepted

## Context

[ADR 0006](0006-native-swiftui-app.md) moves Nowboard to a SwiftUI app for iOS and macOS and put it in `ios/`. Two questions came up as soon as the first Swift code landed: should the Swift app get its own repository, and is `ios/` the right name for an app that also has a macOS target?

## Decision

- The Swift app stays in **this repository**, at least until the Tauri app is archived.
- Its folder is **`apple/`** (not `ios/`), since it holds both the iOS and the macOS targets. The package is `apple/NowboardKit`.

## Alternatives considered

- **A new repository for the Swift app:** a clean history and layout. But the spec and `fixtures/task-format/`, which keep both apps compatible, would have to be copied (and drift) or shared through a git submodule. A format change would no longer be one PR with both test suites in one CI run.
- **Keep `ios/`:** it would mislead once the macOS target exists.

## Consequences

- One copy of the spec and fixtures. A format change updates the spec, the fixtures, `tasks.rs` and `NowboardKit` in one PR, with `cargo test` and `swift test` in one CI run.
- The repo holds two apps for a while (Rust + npm and Swift). Xcode only looks at `apple/`, so they don't get in each other's way.
- When the Tauri app is archived, revisit the layout: tag the last Tauri version (`tauri-final`), move or remove its code, and maybe move `apple/` to the root. If a separate repository is wanted then, `git subtree split --prefix apple` keeps the Swift history.
