# Nowboard

A calm kanban board for your day. Every task is a markdown file in your Obsidian vault.

- **Frontend:** React + TypeScript (`src/`). That's where the design lives.
- **Backend:** Rust with Tauri 2 (`src-tauri/`). It reads and writes the `.md` files, watches the folder for changes, and owns the ⌥ Space shortcut.

The design decisions are in [DESIGN.md](DESIGN.md). Read it before changing how something looks or behaves.

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
- logs each finished task as `- [x] Title` in `<vault>/Daily/YYYY-MM-DD.md`
- reloads automatically when you edit a task file in Obsidian

Settings are saved in `~/Library/Application Support/com.nestoririondo.nowboard/settings.json`.

**Tip:** while developing, run `NOWBOARD_VAULT="/path/to/a/test-vault" npm run app` to use a throwaway vault.

## 4. The global shortcut

⌥ Space brings the window to the front and opens quick add, from any app. macOS may ask for Accessibility permission the first time (System Settings → Privacy & Security → Accessibility). If another app already uses ⌥ Space, change the shortcut in `src-tauri/src/lib.rs` (`Modifiers::ALT, Code::Space`).

## 5. Build a real app

```bash
npm run tauri build
```

This creates `src-tauri/target/release/bundle/macos/Nowboard.app` and a `.dmg`. Drag the app into Applications.

## Project map

```
src/
  App.tsx              page layout: header, Today, Backlog, Done
  useBoard.ts          all state and actions (move, complete, add, edit…)
  useDnd.ts            drag and drop
  api.ts               the only file that talks to Rust (plus the browser demo store)
  themes.ts            the 7 themes and the colour palette
  styles.css           every style and animation
  components/
    Cards.tsx          TodayCard and BacklogCard
    QuickAdd.tsx       the add box
    DetailPanel.tsx    the panel that slides in from the right
    SettingsPopover.tsx
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
| `npm run build` | Type-check and build the frontend |
| `npm run tauri build` | Build `Nowboard.app` |

## Ideas for next steps

1. A small floating quick-add window instead of bringing the whole board forward.
2. A menu-bar icon (Tauri tray) that shows the focus card.
3. A ⌘K command menu.
4. A phone version, using the compact list layout from the design canvas.
