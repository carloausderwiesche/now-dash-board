# Notes for AI assistants working on this repo

- Read DESIGN.md before changing anything visual or behavioural. Keep the principles: one column, no clutter, colour = category, short satisfying animations.
- Follow GUIDELINES.md for frontend code: components only render (props in, `on…` callbacks out), board rules go in `src/board.ts` as tested pure functions, state and API calls in hooks, and `npm run lint && npm test` pass before you're done.
- Colours, radii and fonts come only from `src/themes.ts` (CSS variables). Never hard-code a colour in a component.
- All disk access goes through `src/api.ts` → Rust commands in `src-tauri/src/lib.rs`. Keep `api.ts`'s browser demo store working, so `npm run dev` still shows the design.
- The task file format is specified in `docs/task-format.md` and tested by the shared cases in `fixtures/task-format/`. If you change it, update the spec (`docs/task-format.md`), the fixtures, `tasks.rs` and `NowboardKit`, and run `cargo test` and `swift test`.
- Every PR answers "ADR or not?" (docs/adr/README.md): a change that makes a decision (dependency, file format, structure, a deliberate trade-off) adds an ADR to `docs/adr/` and its index; anything else says "No ADR: <reason>" in the PR description.
- Nestor is learning Rust and Swift. Explain Rust and Swift changes in comments and in plain language.
- The SwiftUI app (iOS + macOS, `ios/`) is replacing the Tauri app ([ADR 0006](docs/adr/0006-native-swiftui-app.md)). Until it reaches parity, the Tauri app only gets bug fixes. Task files are read and written by `NowboardKit` (`ios/NowboardKit`), which must pass `fixtures/task-format/` (`swift test`), like `tasks.rs` does (`cargo test`).
