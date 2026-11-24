# Task format conformance cases

Shared test cases for [the task file format](../../docs/task-format.md). Any program that reads or writes Nowboard task files runs all of them:

- the Tauri app: `cargo test` in `src-tauri/` (runner: `src-tauri/src/tasks/conformance.rs`)
- the SwiftUI app: `swift test` in `apple/NowboardKit/` (runner: `Tests/NowboardKitTests/ConformanceTests.swift`)

The Rust runner is the reference until the Tauri app is archived ([ADR 0006](../../docs/adr/0006-native-swiftui-app.md)). A new rule or a bug found in one app gets a case here first, so both apps learn it.

## One case

A case is a group of files sharing a name like `08-keeps-unknown-fields-and-body`:

| File | What it is |
|---|---|
| `NN-name.expected.json` | Required. What to do and what should come out (below). |
| `NN-name.input.md` | The task file as it is on disk. Missing for a brand-new task. |
| `NN-name.after-save.md` | The file after saving or renaming. Only for cases that write. |

`expected.json` fields:

| Field | Meaning |
|---|---|
| `description` | One sentence: the rule this case checks. |
| `file` | The file name the input is stored under (the title comes from it). For a new task: the name it should be saved as. |
| `modified` | Optional. The file's last-modified time (`YYYY-MM-DDTHH:MM`, local), used by the done-time rule. |
| `task` | Optional. What reading `input.md` must give, in the file format's own field names. `order` is `null` when the file has none (it isn't resolved here). |
| `save` | Optional. Load the file as the only task in an empty folder (so a missing `order` becomes `0`), change these fields, save. |
| `new` | Optional. Save a brand-new task with these fields (missing ones: `backlog`, `personal`, order `0`, everything else empty). |
| `rename` | Optional. Rename the task to this title. |
| `existing` | Optional. Other file names already in the folder before writing (for clash counters). |
| `saved_as` | Optional. The file name after writing, if it's not `file`. |
| `save_error` | Optional. `true` if saving must be refused and the file left exactly as it was. |

After writing, the folder must hold exactly the `existing` files plus `saved_as`: no `.tmp` file, no old name.

## How the written file is compared

The spec says "kept" means the same frontmatter keys, in the same order, with the same values; how values are quoted is up to each implementation. So `after-save.md` is compared like this:

- the file starts with `---\n`;
- the frontmatter is parsed as YAML on both sides; the key order and the values must match;
- the body must match **byte for byte**.

## Other files

- `file-names.json`: titles and the file stem each one must give (`stem_for` in the spec). Note the last cases: 80 characters means 80 Unicode scalars. In Swift, count `unicodeScalars`, not `Character`s.
- `folder/` and `folder.expected.json`: a whole Tasks folder. Only `A.md`, `B.md`, `C.md` and `D.md` are tasks; `B.md` and `D.md` have no order and both go on top (smallest order of all, minus 1024). The hidden, `README.md`, `.txt`, `.MD` and subfolder files must be skipped.

## Traps for a new implementation

- `done: 2026-11-22` must be read as **text**. Some YAML libraries (Yams in Swift, for example) turn it into a date; read the raw scalar instead.
- `focus: "true"` (quoted) is not on, and `order: "5"` (quoted) is not a number (case 21).
- An empty string is missing: `area: ""` means `personal`.
- Removing a field must not move the others. A "swap remove" moves the last field into the gap (case 18).
