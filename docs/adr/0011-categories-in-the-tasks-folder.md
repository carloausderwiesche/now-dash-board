# 0011. Categories live in `.nowboard.json` in the Tasks folder

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

A task stores only its category id (`area: work`). What `work` is called, its colour and the order of the dots were device settings: the Tauri app keeps them in its `settings.json`, the SwiftUI app in `UserDefaults`. Once the iPhone and the Mac share the Tasks folder through iCloud ([ADR 0005](0005-icloud-vault-sync.md)), per-device categories drift apart: a category added on the Mac doesn't exist on the iPhone, so its tasks show in the first category there.

The SwiftUI app only has access to the Tasks folder you picked, not the whole vault.

## Decision

The SwiftUI app keeps the categories in `.nowboard.json` in the Tasks folder, specified in [task-format.md, section 7](../task-format.md#7-the-board-settings-file). It syncs with the tasks. When the file is missing, the app writes its own categories into it (on a Mac that's first launch, copied from the Tauri app's settings). Theme and card size stay per device.

## Alternatives considered

- **Keep them per device:** no new file, but the drift above.
- **iCloud key-value storage (`NSUbiquitousKeyValueStore`):** syncs settings without a file, but only between Apple devices signed into the same account, and Obsidian or an agent can't see it.
- **In the vault's root or `.obsidian/`:** the iPhone app can't reach outside the Tasks folder it was given.

## Consequences

- The iPhone and the Mac show the same categories, in the same order, and an agent can read what `area:` ids mean.
- The file is a dotfile, so it's never mistaken for a task, and Obsidian doesn't show it.
- A broken file (invalid JSON) is never overwritten; the app keeps its own categories and says so in the error bar.
- The Tauri app (bug fixes only, [ADR 0006](0006-native-swiftui-app.md)) doesn't read the file, so `tasks.rs` doesn't implement section 7. While both apps are in use, a category edited in one doesn't show in the other.
