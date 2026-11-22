// The only file that talks to Rust. Inside the Tauri app it calls the
// #[tauri::command] functions in src-tauri/src/lib.rs. In a normal browser
// (`npm run dev`) it falls back to a demo store in localStorage, so you can
// work on the design without the Rust side running.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { Settings, Task } from "./types";

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
/** True inside the small quick-add window that ⌥ Space opens from anywhere. */
export const isQuickWindow = inTauri && getCurrentWindow().label === "quick";

export interface Api {
  getSettings(): Promise<Settings>;
  saveSettings(s: Settings): Promise<void>;
  listTasks(): Promise<Task[]>;
  saveTask(t: Task): Promise<Task>;
  /** Renames the file to match a new title; returns the task with its new id. */
  renameTask(id: string, title: string, order: number): Promise<Task>;
  completeTask(id: string): Promise<Task>;
  deleteTask(id: string): Promise<void>;
  taskPath(id: string): Promise<string>;
  openInObsidian(id: string): Promise<void>;
  /** Opens Finder's "choose a folder" window. Null if cancelled (or in the browser demo). */
  pickFolder(opts?: { title?: string; start?: string }): Promise<string | null>;
  /** Vault folders Obsidian already knows about, most recent first. */
  knownVaults(): Promise<string[]>;
  /** Called when files change on disk (e.g. you edited a task in Obsidian). */
  onTasksChanged(cb: () => void): Promise<() => void>;
  /** Quick-add window only: called each time ⌥ Space shows it. */
  onQuickOpen(cb: () => void): Promise<() => void>;
  /** Quick-add window only: called when it was closed from outside (you clicked elsewhere). */
  onQuickClosed(cb: () => void): Promise<() => void>;
  /** Quick-add window only: hides it again. */
  hideQuick(reason: string): Promise<void>;
  /** Browser demo only: puts the sample tasks and settings back. */
  resetDemo(): void;
}

const tauriApi: Api = {
  getSettings: () => invoke("get_settings"),
  saveSettings: (settings) => invoke("save_settings", { settings }),
  listTasks: () => invoke("list_tasks"),
  saveTask: (task) => invoke("save_task", { task }),
  renameTask: (id, title, order) => invoke("rename_task", { id, title, order }),
  completeTask: (id) => invoke("complete_task", { id }),
  deleteTask: (id) => invoke("delete_task", { id }),
  taskPath: (id) => invoke("task_path", { id }),
  openInObsidian: (id) => invoke("open_in_obsidian", { id }),
  pickFolder: (opts) => invoke("pick_folder", { title: opts?.title ?? null, start: opts?.start ?? null }),
  knownVaults: () => invoke("known_vaults"),
  onTasksChanged: (cb) => listen("tasks-changed", () => cb()),
  onQuickOpen: (cb) => listen("quick-open", () => cb()),
  onQuickClosed: (cb) => listen("quick-closed", () => cb()),
  hideQuick: (reason) => invoke("hide_quick", { reason }),
  resetDemo: () => {},
};

// ---------- browser demo store ----------

/** Same file-name rules as `file_stem_for` in tasks.rs. */
const fileName = (title: string) => {
  const stem = Array.from(title.replace(/[/\\:*?"<>|#^[\]\p{Cc}]/gu, "-").trim()).slice(0, 80).join("").replace(/^[.\s]+|[.\s]+$/g, "");
  return (stem || "Untitled") + ".md";
};
const freeName = (all: Task[], title: string, self?: string) => {
  const base = fileName(title).slice(0, -3);
  for (let n = 1; ; n++) {
    const name = n === 1 ? `${base}.md` : `${base} (${n}).md`;
    if (name.toLowerCase() === self?.toLowerCase() || !all.some((x) => x.id.toLowerCase() === name.toLowerCase())) return name;
  }
};

const today = () => new Date().toLocaleDateString("sv-SE"); // YYYY-MM-DD, local time
const stamp = (daysAgo = 0) => {
  const d = new Date(Date.now() - daysAgo * 864e5), pad = (n: number) => String(n).padStart(2, "0");
  return `${d.toLocaleDateString("sv-SE")}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const DEMO_SETTINGS: Settings = {
  vaultPath: "(browser demo — run `npm run app` for the real thing)",
  tasksFolder: "Notes/Tasks",
  dailyFolder: "Daily",
  theme: "braun",
  categories: [
    { id: "personal", name: "Personal", color: "rose" },
    { id: "work", name: "Work", color: "blue" },
    { id: "freelance", name: "Freelance", color: "amber" },
  ],
};
const t = (title: string, area: string, status: Task["status"], order: number, extra: Partial<Task> = {}): Task =>
  ({ id: fileName(title), title: fileName(title).slice(0, -3), area, status, order, focus: false, created: stamp(), doneOn: status === "done" ? stamp() : null, items: [], notes: "", ...extra });
const DEMO_TASKS: Task[] = [
  t("Review PR for alert thresholds", "work", "today", 1024, {
    focus: true,
    notes: "Check the hysteresis values against the old dashboard before approving.",
    items: [{ text: "Read the diff", done: true }, { text: "Run it locally", done: false }, { text: "Leave comments", done: false }],
  }),
  t("Homepage copy review", "freelance", "today", 2048),
  t("Piano practice", "personal", "today", 3072, { private: true }),
  t("Prep notes for 1-on-1", "work", "today", 4096),
  t("Send November invoice", "freelance", "today", 5120),
  t("Write ADR on the message broker", "work", "backlog", 1024),
  t("Fix the bike brakes", "personal", "backlog", 2048),
  t("Draft portfolio essay", "freelance", "backlog", 3072),
  t("Plan Saturday", "personal", "backlog", 4096),
  t("Update sprint board", "work", "backlog", 5120),
  t("Rust book, chapter 4", "personal", "backlog", 6144),
  t("New invoice template", "freelance", "backlog", 7168),
  t("Team retro format ideas", "work", "backlog", 8192),
  t("Reply to the recruiter thread", "work", "suggested", 1024, { from: "[[Notes/" + today() + "]]" }),
  t("Book train tickets", "personal", "done", 1024),
  t("Fix flaky e2e test", "work", "done", 2048),
  t("Renew passport", "personal", "done", 3072, { doneOn: stamp(2) }),
];

function store<T>(key: string, fallback: T): { get(): T; set(v: T): void } {
  return {
    get() {
      try {
        const raw = localStorage.getItem(key);
        return raw ? (JSON.parse(raw) as T) : structuredClone(fallback);
      } catch {
        return structuredClone(fallback);
      }
    },
    set(v) {
      try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* private mode */ }
    },
  };
}
const demoTasks = store<Task[]>("nowboard-demo-tasks-v1", DEMO_TASKS);
const demoSettings = store<Settings>("nowboard-demo-settings", DEMO_SETTINGS);

const demoApi: Api = {
  async getSettings() { return demoSettings.get(); },
  async saveSettings(s) { demoSettings.set(s); },
  async listTasks() { return demoTasks.get(); },
  async saveTask(task) {
    const all = demoTasks.get();
    let saved = { ...task, created: task.created ?? stamp() };
    if (!saved.id) {
      const id = freeName(all, saved.title);
      saved = { ...saved, id, title: id.slice(0, -3) };
    }
    demoTasks.set([...all.filter((x) => x.id !== saved.id), saved]);
    return saved;
  },
  async renameTask(id, title) {
    const all = demoTasks.get();
    const newId = freeName(all, title, id);
    const renamed = { ...all.find((x) => x.id === id)!, id: newId, title: newId.slice(0, -3) };
    demoTasks.set(all.map((x) => (x.id === id ? renamed : x)));
    return renamed;
  },
  async completeTask(id) {
    const all = demoTasks.get();
    const done = { ...all.find((x) => x.id === id)!, status: "done" as const, focus: false, doneOn: stamp() };
    demoTasks.set(all.map((x) => (x.id === id ? done : x)));
    return done;
  },
  async deleteTask(id) { demoTasks.set(demoTasks.get().filter((x) => x.id !== id)); },
  async taskPath(id) { return "Tasks/" + id; },
  async openInObsidian(id) { console.info("In the desktop app this opens Tasks/" + id + " in Obsidian."); },
  async pickFolder() { console.info("In the desktop app this opens Finder to choose a folder."); return null; },
  async knownVaults() { return []; },
  async onTasksChanged() { return () => {}; },
  async onQuickOpen() { return () => {}; },
  async onQuickClosed() { return () => {}; },
  async hideQuick() {},
  resetDemo() {
    try { localStorage.removeItem("nowboard-demo-tasks-v1"); localStorage.removeItem("nowboard-demo-settings"); } catch { /* ignore */ }
    location.reload();
  },
};

export const api: Api = inTauri ? tauriApi : demoApi;
