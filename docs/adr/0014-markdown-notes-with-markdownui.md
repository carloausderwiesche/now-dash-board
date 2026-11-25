# 0014. The SwiftUI app shows notes as Markdown with MarkdownUI

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

Task notes are Markdown, written in Obsidian as often as in Nowboard. The card panel showed them as plain text, so `**bold**`, headings, lists and links read as raw syntax. We want them to look the way Obsidian's Reading view shows them, including the two bits of Obsidian syntax that show up in task notes: `[[wikilinks]]` and `#tags`.

SwiftUI's own `AttributedString(markdown:)` only covers inline styling (bold, italic, code, links). It doesn't lay out headings, lists, quotes, code blocks or tables.

## Decision

- Notes show **rendered** in the panel; a tap (or click) edits the Markdown as stored, and leaving the editor (a click anywhere else in the panel) shows it rendered again. Empty notes go straight to the editor. The file is never rewritten by the renderer.
- Rendering uses **[MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)** (`from: "2.4.0"`), a GitHub-flavoured Markdown renderer for SwiftUI, styled with the theme's font, ink, accent and well colours. It's a dependency of the app target only, not of `NowboardKit`.
- Obsidian syntax is turned into plain Markdown before rendering, in `NowboardKit` (`obsidianToMarkdown`, tested without UI): `[[Note|alias]]` and `![[embed]]` become links that open the note in Obsidian (`obsidian://open?vault=…&file=…`), `#tag` becomes a link to Obsidian's search for that tag. Code spans and fenced code are left alone. The vault is the nearest folder above the Tasks folder with `.obsidian`; without one (the demo board) wikilinks show as text and tags stay as they are.

## Alternatives considered

- **Live Preview** (rendered while typing, like Obsidian's default editor): iOS 26 / macOS 26 can edit styled text, but keeping the file byte-for-byte while hiding the syntax is a big job. We'd revisit it once Reading view has proven itself.
- **Apple's `swift-markdown` parser with our own renderer:** full control and an Apple package, but a block renderer (lists, tables, quotes) is a lot of code to own for the same result.
- **A web view with a JavaScript renderer** (as the Tauri app could): one more process per panel, and text that doesn't feel native.
- **Tags as pills:** MarkdownUI styles all links alike, so tags look like links. Pills would need our own inline renderer.

## Consequences

- Notes read like they do in Obsidian; wikilinks and tags jump into Obsidian.
- One more dependency to keep up to date. MarkdownUI is mature and widely used, but in maintenance mode (its author is working on a successor); we'd move if it stops building.
- Obsidian extras beyond wikilinks and tags (callouts, `==highlights==`, math, embedded notes) show as their raw text for now.
