# Notes for AI assistants working on this repo

- Read DESIGN.md before changing anything visual or behavioural. Keep the principles: one column, no clutter, colour = category, short satisfying animations.
- Follow GUIDELINES.md for frontend code: components only render (props in, `on…` callbacks out), board rules go in `src/board.ts` as tested pure functions, state and API calls in hooks, and `npm run lint && npm test` pass before you're done.
- Colours, radii and fonts come only from `src/themes.ts` (CSS variables). Never hard-code a colour in a component.
- All disk access goes through `src/api.ts` → Rust commands in `src-tauri/src/lib.rs`. Keep `api.ts`'s browser demo store working, so `npm run dev` still shows the design.
- The task file format is documented in DESIGN.md and tested in `src-tauri/src/tasks.rs`. If you change it, update both and run `cargo test`.
- Every PR answers "ADR or not?" (docs/adr/README.md): a change that makes a decision (dependency, file format, structure, a deliberate trade-off) adds an ADR to `docs/adr/` and its index; anything else says "No ADR: <reason>" in the PR description.
- Nestor is learning Rust. Explain Rust changes in comments and in plain language.
