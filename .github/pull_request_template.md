## What and why

<!-- What changes, and the reason. Link the issue if there is one. -->

## ADR

<!-- Pick one (see docs/adr/README.md):
     - Adds/updates docs/adr/NNNN-….md: one line on the decision
     - No ADR: one line on why (e.g. "bug fix, no new decision") -->

## Checks

- [ ] `npm run format:check && npm run lint && npm test && npm run build`
- [ ] `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test` (in `src-tauri/`)
- [ ] Tried it in the app or the browser demo (`npm run dev`)
