# Vault change conformance cases

Shared test cases for [vault changes](../../docs/vault-changes.md).

## `link-rewrite.json`

`{"cases": [...]}`. Each case moves or renames one note and rewrites the links in a text:

| Field | Meaning |
|---|---|
| `description` | One sentence: the rule this case checks. |
| `old`, `new` | The note's path before and after (vault-relative, ending in `.md`). |
| `notes` | Every note in the vault before the move, `old` included. |
| `input` | The text to rewrite. |
| `expected` | The text afterwards, byte for byte (line breaks included). |
| `changed` | How many links must be changed. |
| `ambiguous` | How many links must be left alone because they could mean another note. |

Run by `Tests/NowboardKitTests/WikiLinksTests.swift` (`swift test` in `apple/NowboardKit/`).
