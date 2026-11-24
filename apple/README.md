# Nowboard for iPhone and Mac (SwiftUI)

The native app that replaces the Tauri app ([ADR 0006](../docs/adr/0006-native-swiftui-app.md)). One SwiftUI target builds for both iOS and macOS. It reads and writes the same task files, following [docs/task-format.md](../docs/task-format.md).

| Folder | What's in it |
|---|---|
| `NowboardKit/` | The task file format: reading, writing, file names. No UI. `swift test` runs it against `fixtures/task-format/`. |
| `Nowboard/` | The app: themes, the board and its views. Platform-only code sits behind `#if os(iOS)` / `#if os(macOS)`. |
| `project.yml` | The Xcode project as text ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). |

## Build and run

Needs Xcode (with the iOS platform installed: Xcode → Settings → Components) and XcodeGen (`brew install xcodegen`).

```sh
cd apple
xcodegen              # writes Nowboard.xcodeproj (not in git; run again after changing project.yml)
open Nowboard.xcodeproj
```

In Xcode, pick an iPhone simulator or "My Mac" and press ⌘R.

Tests for the file format, from the terminal:

```sh
cd apple/NowboardKit && swift test
```

## Trying it

The app starts with the same demo board as the browser demo. Settings (the slider button) → **Choose Tasks folder…** reads a real folder instead. Use a **copy** of a Tasks folder while the app is young; it only reads for now, but that's the rule until it's in daily use.

The bundle id is `com.nestoririondo.nowboard.swiftui`, so it can sit next to the Tauri app on the Mac.
