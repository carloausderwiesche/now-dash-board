# Capture conformance cases

Shared test cases for [the capture format](../../docs/capture-format.md). Any program that reads the classifier's answer, checks a model-chosen path or writes captures runs all of them:

- the SwiftUI app: `swift test` in `apple/NowboardKit/` (runner: `Tests/NowboardKitTests/CaptureConformanceTests.swift`)

A new rule, or a bug found in one implementation, gets a case here first.

## `classifier/`

One JSON file per case. Fields:

| Field | Meaning |
|---|---|
| `description` | One sentence: the rule this case checks. |
| `categories` | The board's category ids, in order. |
| `input` | The classifier's answer, as JSON. |
| `input_text` | Instead of `input`: the answer as raw text (for text that isn't JSON). |
| `expected` | `{"error": true}` if reading must fail. Otherwise the result: `kind`, `title`, `body`, `area`, `status`, `folder`, `confidence`, `follow_up` (`null` when missing), `needs_question` (is the person asked?) and `question` (what is asked, or `null`). |

## `cli-output/`

What the claude tool printed, and what reading it must give. `NN-name.stdout` is the raw output (it may be broken on purpose); `NN-name.expected.json` has `description` and either `error` (a `ClassifierError` case: `cliReportedError`, `noStructuredOutput`, `invalidResult`, `unreadableOutput`) with an optional `message_contains`, or the result: `kind`, `title`, `confidence`, optional `area`, and the diagnostics `cost`, `input_tokens`, `output_tokens`, `duration_ms` (`null` when the output has none). Categories are always `personal`, `work`.

## `daily-note/`

A case is a group of files sharing a name like `01-heading-at-end`:

| File | What it is |
|---|---|
| `NN-name.case.json` | `description` and the `line` to add. |
| `NN-name.input.md` | The note's text before. May be empty. Compared byte for byte, line breaks included. |
| `NN-name.after.md` | The text after adding the line, byte for byte. |

## `vault-paths.json`

`file_paths` and `folder_paths`: a path, whether it's `valid`, and the `normalized` path when it is. Hostile paths are here on purpose; add more whenever you think of one.

## `raw-captures.json`

Cases for the raw capture file: the typed `text`, the `time` (local time in the file's `time_zone`), the file names that `existing` in the Inbox, and the `file` name and `content` that must be written. `refused_texts` must be refused and write nothing.
