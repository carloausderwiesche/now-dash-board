# Nowboard

A calm kanban board for your day. Every task is a markdown file in your Obsidian vault.

**[Try the clickable demo →](https://nestoririondo.github.io/nowboard/)** (sample data, runs in your browser)

## What it does

Nowboard answers one question: *what am I doing today?*

- **One column:** Today (big cards), Backlog (small cards), Done (a counter for today, the last 7 days on click).
- **Throw, don't schedule:** no times or estimates. Drag cards between lists, tick them off, optionally put one card in *Focus*.
- **Colour = category** (e.g. Work, Personal, Freelance). Click a colour in the header to highlight just that category.
- **Your tasks are plain files.** Each task is a `.md` file in your Obsidian vault (`Notes/Tasks/`), with a little frontmatter for status, category and order. Edit them in Obsidian, sync them with anything, let scripts or AI agents read them or *suggest* new tasks. The app watches the folder and keeps unknown fields untouched.
- **Quick add from anywhere:** ⌥ Space opens a small floating box over whatever you're doing.
- **Themes** inspired by Dieter Rams, Jony Ive, Charles & Ray Eames and soft pastels.

- **Frontend:** React + TypeScript (`src/`). That's where the design lives.
- **Backend:** Rust with Tauri 2 (`src-tauri/`). It reads and writes the `.md` files, watches the folder for changes, and owns the ⌥ Space shortcut.

The design decisions are in [DESIGN.md](DESIGN.md). Read it before changing how something looks or behaves. How the frontend code is organised (components, hooks, business logic, re-renders, tests) is in [GUIDELINES.md](GUIDELINES.md). Why things are the way they are is recorded as decision records in [docs/adr/](docs/adr/README.md); every pull request either adds one or says why it doesn't need one.

## 1. Install the tools (once)

On your Mac, in Terminal:

```bash
# Xcode command line tools: compilers that Rust needs on macOS
xcode-select --install

# Rust: installs rustc (compiler) and cargo (package manager) into ~/.cargo
curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh

# Node 18+ — skip if `node -v` already prints a version
brew install node
```

Restart the terminal afterwards so `cargo` is on your PATH.

## 2. Open and run

```bash
cd nowboard
code .            # opens VS Code; accept the recommended extensions
npm install       # frontend packages
npm run app       # builds the Rust side and opens the app window
```

The first `npm run app` compiles all the Rust dependencies, which takes a few minutes. After that it starts in seconds.

To work only on the design, run `npm run dev` and open http://localhost:1420 in your browser. That uses demo data from `src/api.ts` and doesn't touch your vault.

## 3. Point it at your vault

Click the settings button (the sliders icon) and pick your vault from the list (the vaults Obsidian
already knows), or choose "Other folder…" to select it in Finder.

The app then:

- reads and writes tasks in `<vault>/Notes/Tasks/`, one file per task (format in DESIGN.md)
- logs each finished task as `- [x] Title` in a daily note, `<vault>/Daily/YYYY-MM-DD.md` by default (change the folder in Settings → "Finished tasks are logged in")
- reloads automatically when you edit a task file in Obsidian

Settings are saved in `~/Library/Application Support/com.nestoririondo.nowboard/settings.json`.

**Tip:** while developing, run `NOWBOARD_VAULT="/path/to/a/test-vault" npm run app` to use a throwaway vault.

## 4. The global shortcut

⌥ Space opens a small floating quick-add box from any app, without bringing the board forward (on macOS it's a non-activating panel, via `tauri-nspanel`). macOS may ask for Accessibility permission the first time (System Settings → Privacy & Security → Accessibility). If another app already uses ⌥ Space, change the shortcut in `src-tauri/src/lib.rs` (`Modifiers::ALT, Code::Space`).

## 5. Build a real app

```bash
npm run tauri build
```

This creates `src-tauri/target/release/bundle/macos/Nowboard.app` and a `.dmg`. Drag the app into Applications.

Or in one step: `npm run install-app` builds the app and replaces `/Applications/Nowboard.app` with it. Quit Nowboard first, then run it again after changing the code.

## Project map

```
src/
  App.tsx              page layout: wires the board to the sections below
  useBoard.ts          all task state and actions (move, complete, add, edit…)
  board.ts             the pure logic behind them: ordering, moves (with tests)
  useSettings.ts       settings state, saved shortly after each change
  useCompletion.ts     the "done" animation and its queue
  useDnd.ts            drag and drop (with the drop preview, tested)
  useFlip.ts           cards gliding to their new place
  QuickWindow.tsx      the ⌥ Space window (quick add only)
  api.ts               the only file that talks to Rust (plus the browser demo store)
  themes.ts            the 9 themes and the colour palette
  styles.css           every style and animation
  components/
    Header.tsx         date, category filter, settings and + buttons
    Sections.tsx       Today/Backlog list, Suggested, Done
    Cards.tsx          TodayCard and BacklogCard
    QuickAdd.tsx       the add box
    DetailPanel.tsx    the panel that slides in from the right
    SettingsPopover.tsx
    DemoIntro.tsx      explanation shown only in the browser demo
src-tauri/
  src/lib.rs           commands the frontend calls, file watcher, ⌥ Space
  src/tasks.rs         markdown file ⇄ Task (with tests)
  src/settings.rs      settings.json
  tauri.conf.json      window size, app name, bundle
```

## Useful commands

| Command | What it does |
|---|---|
| `npm run app` | Run the desktop app with hot reload |
| `npm run dev` | Frontend only, in the browser, with demo data |
| `cd src-tauri && cargo test` | Run the Rust tests (parsing and writing task files) |
| `npm test` | Run the frontend tests (Node's built-in test runner, Node 22+) |
| `npm run lint` | ESLint, including the React hooks rules |
| `npm run build` | Type-check and build the frontend |

`.github/workflows/ci.yml` runs all of these, plus `cargo fmt --check` and `cargo clippy -- -D warnings`, on every push and pull request.
| `npm run tauri build` | Build `Nowboard.app` |

## Ideas for next steps

1. A menu-bar icon (Tauri tray) that shows the focus card.
2. A ⌘K command menu.
3. A phone version, using the compact list layout from the design canvas.

## Web demo

`.github/workflows/demo.yml` builds the frontend with its browser demo store and publishes it to GitHub Pages on every push to `main`. Locally: `npm run build -- --base=/nowboard/ && npx vite preview --base=/nowboard/`.

## License

MIT, see [LICENSE](LICENSE).
