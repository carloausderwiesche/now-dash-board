// Mirrors the Rust structs in src-tauri/src/tasks.rs and settings.rs.

export type Status = "today" | "backlog" | "done" | "suggested";

export interface ChecklistItem {
  text: string;
  done: boolean;
}

export interface Task {
  /** File name in the Tasks folder, e.g. "Fix k6 nightly token.md". Empty = not saved yet. */
  id: string;
  /** The file name without ".md". Editing it renames the file. */
  title: string;
  status: Status;
  /** Id of a Category (`area:` in the file). */
  area: string;
  /** The one card you're working on right now (optional). */
  focus: boolean;
  /** Float, smaller = higher. Moving a card sets it to the midpoint of its neighbours. */
  order: number;
  /** Timestamps like "2026-11-22T09:40". */
  created?: string | null;
  doneOn?: string | null;
  project?: string | null;
  /** Only on agent-suggested tasks, e.g. "[[Notes/2026-11-22]]". */
  from?: string | null;
  /** `#private` in the body. Read-only. */
  private?: boolean;
  items: ChecklistItem[];
  notes: string;
}

export type PaletteKey =
  | "rose" | "red" | "orange" | "amber" | "green" | "teal" | "cyan"
  | "blue" | "indigo" | "violet" | "pink" | "brown" | "slate";

export interface Category {
  id: string;
  name: string;
  color: PaletteKey;
}

export type ThemeKey = "braun" | "graphite" | "aluminium" | "spacegrey" | "peach" | "mint" | "lavender";

export interface Settings {
  vaultPath: string;
  tasksFolder: string;
  dailyFolder: string;
  theme: ThemeKey;
  categories: Category[];
}
