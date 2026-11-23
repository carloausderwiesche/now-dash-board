# 0002. Prettier formats the frontend, checked in CI

- **Date:** 2026-11-23
- **Status:** Accepted

## Context

The Rust side is formatted by `cargo fmt` and checked in CI. The TypeScript had no formatter, so its style depended on whoever (or whichever AI assistant) edited a file last. That makes diffs noisy and review slower.

## Decision

Use Prettier for everything in `src/` (TypeScript, TSX, CSS), with a line width of 140. `npm run format` fixes formatting, and `npm run format:check` runs in CI.

## Alternatives considered

- **ESLint style rules:** slower, more config, and the ESLint team itself recommends a formatter for this.
- **Biome:** faster and lints too, but adopting it means replacing the ESLint setup we just added. Worth a look if ESLint ever gets slow.
- **Prettier's default 80 columns:** the code was written with long, dense lines. 80 would wrap almost every line, 140 keeps most of them.

## Consequences

- No more formatting discussions. The first run reformats most of `src/` once, best committed on its own so it doesn't hide real changes.
- Prettier spreads compact one-liners (`if (x) { a(); b(); }`) over several lines. The code gets longer but easier to diff.
- Markdown files aren't formatted (not in `src/`), so the docs' tables stay as written.
