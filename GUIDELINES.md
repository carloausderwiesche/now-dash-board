# Nowboard — development guidelines (React frontend)

How the code in `src/` is organised and why. [DESIGN.md](DESIGN.md) covers how things look and behave; this file covers how to build them. Every rule names an example from this codebase, so you can see it in practice.

## 1. Every piece of code has one home

The frontend has five layers. Code only depends on layers to its right in this list, never on ones to its left:

`components/` → hooks (`use*.ts`) → `board.ts` / `api.ts` → `types.ts`

| Layer | Holds | Must not | Example |
|---|---|---|---|
| **Components** (`components/*.tsx`) | Markup, styling hooks (class names), local UI state like "is this open" | Call `api`, contain board rules, know about files or Rust | `Cards.tsx`, `Sections.tsx`, `Header.tsx` |
| **Hooks** (`use*.ts`) | React state, effects, wiring logic to the API, error state | Render markup | `useBoard.ts`, `useSettings.ts`, `useCompletion.ts`, `useDnd.ts` |
| **Business logic** (`board.ts`) | Pure functions: ordering, moves, "what changed on disk" | Import React or `api`, touch the DOM, read the clock unless it has to (`nowStamp` is the one exception) | `planMove`, `topOrder`, `splitFinished` |
| **Data access** (`api.ts`) | Every call to Rust, plus the browser demo store | Hold UI state | `api.saveTask`, `api.onTasksChanged` |
| **Types** (`types.ts`) | Shapes shared by all layers, mirroring the Rust structs | Logic | `Task`, `Status`, `Settings` |

`App.tsx` is the one place that puts these together: it calls the hooks, works out the lists to show, and passes data and callbacks down. It should read like a table of contents, not like an implementation.

**Why:** when a bug is about *what* happens (a card lands in the wrong place), you look in `board.ts`. When it's about *when* it happens (a save fires twice), you look in a hook. When it's about *how it looks*, you look in a component. Nobody has to read all three.

## 2. One component, one job

- If you need "and" to describe a component ("shows the header **and** handles the filter **and** the settings"), split it.
- Rough size signal: past ~150 lines, look for a piece to pull out. Past 250, definitely.
- Small related components may share a file (`Sections.tsx` holds the three list sections). One file per component is fine too. Keep components that change together in the same file.
- Repeated JSX is a component waiting to be named. `CardSection` exists because Today and Backlog had the same heading, grid and empty state.

## 3. Presentational, reusable components

Most components should be *presentational*: they get data through props, render it, and report what the user did through callbacks. They don't know where the data comes from or what happens next.

- **Data in, events out.** Props are plain data (`task`, `categories`, `count`). User actions are `on…` callbacks (`onOpen`, `onComplete`, `onUndo`). A component says *what the user did* (`onUndo(id)`), never *what to do about it* (no `board.move(...)` inside).
- **Pass what's needed, not whole objects.** Prefer `colourOf: (area) => string` over passing all of `settings` and the theme. Never pass the whole `board` hook result into a component: it hides what the component really uses and ties it to `useBoard`.
- **No data fetching in components.** Components never import `api`. If a component needs data, a hook loads it and passes it in.
- **Local UI state is fine.** "Is the Done list expanded" belongs in `DoneSection` itself, not in `App`. That's still presentational: nobody outside needs to know.
- **Styling:** static styles go in `styles.css`. Inline `style` only for values computed at runtime (a category colour, a measured offset). Colours, radii and fonts only come from `themes.ts` (see AGENTS.md).
- **Accessible by default:**
  - Real `<button>`s for anything clickable, `aria-label` on icon-only buttons, `aria-expanded`/`aria-pressed` on toggles (the header's filter dots show the pattern).
  - **Dialogs manage focus.** When a dialog opens (detail panel, settings, quick add), focus moves into it (`QuickAdd` focuses its input). When it closes, focus goes back to whatever opened it, so keyboard users don't land at the top of the page.
  - **Everything has a keyboard path.** Drag-and-drop is a shortcut, not the only way: moving between lists also works with buttons ("Today ↑", Undo, the Today/Backlog switch in the detail panel).
  - **Respect "Reduce motion".** Animations are part of the design, but under `@media (prefers-reduced-motion: reduce)` they become instant or a short fade. No flying, sliding or bumping. (macOS: System Settings → Accessibility → Display → Reduce motion.)

## 4. Business logic is pure and lives in `board.ts`

- A function that decides something about tasks (where a card goes, which order a new one gets, what counts as "finished elsewhere") is a pure function: same input, same output, no side effects.
- The hook *calls* the function and *applies* the result (`move` calls `planMove`, then sets state and saves). The function never sets state or saves anything itself.
- If you write an `if` about tasks inside a component or a hook, ask whether it's a board rule. If it is, move it to `board.ts` and test it there.

## 5. Data fetching and side effects stay in hooks

- `api.ts` is the only file that talks to Rust. Hooks call `api`; components and `board.ts` never do.
- **Optimistic updates:** update React state first so the UI responds instantly, then write the file (`patch`, `move`). If the write fails, show the error. Don't silently keep a state that isn't on disk.
- **Every `catch` does something visible:** set the hook's `error` state (shown in the error bar), or fall back on purpose and say so in a comment (`knownVaults` → empty list). An empty `catch {}` needs a comment explaining why ignoring is safe.
- **Effects are for syncing with the outside world**: event listeners, the DOM, timers, the API. Don't use an effect to compute a value from props or state; compute it during render.
- **Every effect cleans up everything it started**: listeners, timers, animation frames. Tauri's `listen` is async, so the cleanup can run *before* the subscription exists. React Strict Mode does exactly that in development: it mounts, unmounts and mounts again. Always subscribe through `cleanupFor` from `api.ts`, never with `.then((u) => (unlisten = u))`, which leaks a listener:

  ```ts
  useEffect(() => cleanupFor(api.onQuickOpen(show), api.onQuickClosed(hide)), []);
  ```
- **Ignore stale responses.** When the same request can run twice (a reload while another is still on its way), a slower old answer can arrive last and overwrite the new one. Number the requests and only apply the latest, or cancel the old one with an `AbortController`. Also drop answers that arrive after the component is gone.
- **A crash shows a screen, not a blank window.** `ErrorBoundary` (in `main.tsx`) catches errors thrown while rendering and offers a reload. It doesn't catch errors in event handlers or async code: those still go through `catch` and error state. A new window or a big independent area (say, a future menu-bar view) gets its own boundary, so one part failing doesn't take down the rest.
- **Dependency lists must be complete.** ESLint's `react-hooks/exhaustive-deps` checks this. If you really have to disable it, add the reason on the same line (see the `incoming` effect in `App.tsx`).

## 6. Logging

- No `console.*` in components, hooks or `board.ts`. Errors reach the user through error state, not the console.
- The demo store in `api.ts` may log to explain what the desktop app would do (`openInObsidian`). That's user-facing text, not debugging.
- Debug output belongs on the Rust side, behind `#[cfg(debug_assertions)]` like the quick-window messages in `lib.rs`, so it never ships in a release build.
- Temporary `console.log`s while debugging are fine. Remove them before committing.

## 7. State: as little as possible, as low as possible

- **One source of truth.** Tasks live in `useBoard`, settings in `useSettings`. Don't copy them into a component's state; read them from props.
- **Derive, don't store.** "Today's cards, sorted" is computed from `tasks` on every render (`inList("today")` in `App.tsx`). Storing it in its own `useState` would let the two drift apart.
- **Keep state where it's used.** Move it down to the lowest component that needs it (`DoneSection`'s `open`). Move it up only when a sibling needs it too.
- **Refs for values the screen doesn't show:** timers, "when did we last write", the latest tasks for a callback (`tasksRef`, `saveTimers` in `useBoard`). Changing a ref doesn't re-render.
- **Name your timings.** A delay that has to match a CSS animation is a named constant with a comment pointing at the CSS (`COMPLETE_MS` in `useCompletion.ts`).

## 8. Avoiding unnecessary re-renders

At this size, clear code matters more than squeezing out renders. React is fast at re-rendering a few dozen cards. So **measure first, then optimise**: React DevTools → Profiler, or "Highlight updates when components render". Do the cheap, structural things always, and the memoisation only when the Profiler shows a real cost.

Always:

- **Keep fast-changing state low.** State that changes often (drag position, hover, typing) should live in the smallest component or hook that needs it, so only that part re-renders.
- **Per-frame updates bypass React.** Anything that moves every frame goes through a ref, the DOM or CSS, not state. The drag clone in `useDnd.ts` follows the pointer via `style.transform`; only *where it would land* is React state, and even that waits for the pointer to settle (`SETTLE_MS`).
- **Stable `key`s.** Always the task's `id`, never the array index. Index keys make React re-create cards when the order changes, which also breaks the FLIP slide animation.
- **No derived state through effects.** `useEffect(() => setX(f(y)), [y])` renders twice for every change. Compute `f(y)` during render instead.
- **Don't create new objects for no reason** in props that go deep, for example a new `[]` or `{}` default on every render. Use a constant outside the component.

Only when the Profiler shows a real cost:

- **`React.memo` + stable props, together.** `memo` only helps if *every* prop stays the same between renders. Inline callbacks like `onOpen={() => setOpenId(t.id)}` are new each render and defeat it. So memoising the cards means first changing callbacks to take the id (`onOpen(id)`) and passing a `useCallback` from above.
- **`useMemo` for expensive calculations**, not for cheap ones like filtering 30 tasks. It has its own cost and makes the code harder to read.
- **Context only for values that rarely change** (the theme, say), never for tasks or drag state: every consumer re-renders on every change.

Looking ahead: the project is on React 18. React 19 adds the **React Compiler**, which memoises automatically, so most of the list above stops being your job. React 19.2 also adds **`useEffectEvent`**, which replaces the `eslint-disable` in `App.tsx`'s `incoming` effect. When upgrading, adopt both and simplify this section.

## 9. Testing

- Pure logic gets tests: everything in `board.ts`, plus pure helpers exported from hooks (`dropPreview` in `useDnd.ts`). Tests sit next to the file (`board.test.ts`) and run with `npm test` (Node's built-in runner).
- Name tests after behaviour (`"spaces the whole list out again when the neighbours share an order"`), not after the function.
- Keeping logic out of components (sections 3 and 4) is what makes this possible. If something is hard to test, that's usually a sign it's in the wrong layer.
- Components and animations aren't covered by tests. Check them by hand in the browser demo (`npm run dev`).
- The file format and disk behaviour are tested in Rust (`cargo test`, see AGENTS.md).

## 10. TypeScript

- `strict` is on and stays on. No `any`: if a type really is unknown (parsed JSON, say), use `unknown` and check it.
- **No `!` (non-null assertion) and no `as` (cast) to make an error go away.** Both tell the compiler "trust me" and turn off its check right where a bug would be. Handle the missing case instead (`?.`, `??`, an early `return`), or fix the type at its source. The exceptions are DOM lookups React can't type (`document.getElementById("root") as HTMLElement`), each with a reason.
- **Make wrong states impossible.** Use union types instead of loose strings (`Status = "today" | "backlog" | …`, mirrored by the Rust `enum Status`), and optional fields only when "missing" really means something.
- Shared shapes live in `types.ts` and mirror the Rust structs. Change both in the same PR.

## 11. Decisions get an ADR

Every PR either adds an architecture decision record to [`docs/adr/`](docs/adr/README.md) or says in its description why it doesn't need one. Adding a dependency, changing the file format, changing this guide's structure, or breaking one of its rules on purpose all need an ADR. That README explains when and how.

## 12. Before you commit

```bash
npm run format:check && npm run lint && npm test && npm run build
cd src-tauri && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

`npm run format` fixes formatting (Prettier for TypeScript, CSS and JSON; `cargo fmt` for Rust). Formatting is never discussed in review: the tools decide. CI (`.github/workflows/ci.yml`) runs the same checks on every push and pull request.

## Where the code doesn't follow this yet

Fix these when you touch the file anyway. They're not urgent:

- `SettingsPopover` gets the whole `board` and calls `api.pickFolder` / `api.knownVaults` itself. It should get `settings` plus callbacks (`onChange`, `onPickFolder`), with the API calls moved into `useSettings`.
- `DemoIntro` calls `api.resetDemo` directly. That's acceptable for a demo-only button, but it would be cleaner as an `onReset` prop.
- `App.finish` measures the card with `document.querySelector` to aim the fly animation. DOM measuring belongs in a small hook, next to `useFlip`.
- **Reduce motion isn't supported yet.** `styles.css` has no `prefers-reduced-motion` rules.
- **Dialogs don't return focus** to the button that opened them, and the detail panel doesn't move focus in when it opens.
- **`useBoard.reload` doesn't ignore stale responses.** A file-change reload and a settings reload can overlap.
- A few `!` and `as` remain, for example `catOf(filter!)` and `settings.theme as ThemeKey` in `App.tsx`.
- React 18, see the end of section 8.
