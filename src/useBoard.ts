// All board state and every action (move, complete, edit…) in one hook.
// Pattern: update React state first (instant UI), then write the file.

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "./api";
import { PALETTE_KEYS } from "./themes";
import type { Category, Settings, Status, Task } from "./types";

export const todayStr = () => new Date().toLocaleDateString("sv-SE"); // YYYY-MM-DD, local time
/** Local time as "2026-11-22T09:40", the format of `created:` and `done:`. */
export const nowStamp = () => {
  const d = new Date(), pad = (n: number) => String(n).padStart(2, "0");
  return `${todayStr()}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const STEP = 1024; // gap between orders: new tasks go 1024 above the top one
const byOrder = (a: Task, b: Task) => a.order - b.order || a.title.localeCompare(b.title);
const slug = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "") || "category";

export function useBoard() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [completing, setCompleting] = useState<string | null>(null);
  const [arrived, setArrived] = useState<string | null>(null);
  const [bump, setBump] = useState(false);
  const [lastDone, setLastDone] = useState<string | null>(null);

  const tasksRef = useRef<Task[]>([]);
  tasksRef.current = tasks;
  const lastLocalWrite = useRef(0);
  const saveTimers = useRef(new Map<string, number>());

  // ---------- loading ----------
  const reload = useCallback(async () => {
    try {
      setTasks(await api.listTasks());
      setError(null);
    } catch (e) {
      setError(String(e));
      setTasks([]);
    }
  }, []);

  useEffect(() => {
    api.getSettings().then(setSettings);
    reload();
    let unlisten: (() => void) | undefined;
    let t: number | undefined;
    api.onTasksChanged(() => {
      // Ignore the echo of our own writes, and never reload mid-typing.
      if (Date.now() - lastLocalWrite.current < 1200 || saveTimers.current.size > 0) return;
      window.clearTimeout(t);
      t = window.setTimeout(reload, 200);
    }).then((u) => (unlisten = u));
    return () => unlisten?.();
  }, [reload]);

  // ---------- writing ----------
  const persist = useCallback(async (task: Task) => {
    lastLocalWrite.current = Date.now();
    try {
      const saved = await api.saveTask(task);
      lastLocalWrite.current = Date.now();
      if (saved.id !== task.id) {
        setTasks((all) => all.map((x) => (x.id === task.id ? saved : x)));
        setArrived((a) => (a === task.id ? saved.id : a));
      }
      return saved;
    } catch (e) {
      setError(String(e));
      return task;
    }
  }, []);

  /** Text edits are saved 500 ms after you stop typing. */
  const persistSoon = useCallback((task: Task) => {
    const timers = saveTimers.current;
    window.clearTimeout(timers.get(task.id));
    timers.set(task.id, window.setTimeout(() => {
      timers.delete(task.id);
      const latest = tasksRef.current.find((x) => x.id === task.id);
      if (latest) persist(latest);
    }, 500));
  }, [persist]);

  const patch = useCallback((id: string, p: Partial<Task>, opts: { soon?: boolean } = {}) => {
    const current = tasksRef.current.find((x) => x.id === id);
    if (!current) return;
    const next = { ...current, ...p };
    setTasks((all) => all.map((x) => (x.id === id ? next : x)));
    if (opts.soon) persistSoon(next); else persist(next);
  }, [persist, persistSoon]);

  /** Moves a card into `status`, before `beforeId` or at the end.
   *  Fractional ordering: the card gets the midpoint of its two neighbours'
   *  orders, so only this one file is rewritten. */
  const move = useCallback((id: string, status: Status, beforeId?: string) => {
    if (id === beforeId) return;
    const all = tasksRef.current;
    const moving = all.find((x) => x.id === id);
    if (!moving) return;
    const list = all.filter((x) => x.status === status && x.id !== id).sort(byOrder);
    let at = beforeId ? list.findIndex((x) => x.id === beforeId) : list.length;
    if (at < 0) at = list.length;
    const prev = list[at - 1], next = list[at];
    const order = prev && next ? (prev.order + next.order) / 2 : next ? next.order - STEP : prev ? prev.order + STEP : 0;
    const updated: Task = {
      ...moving, status, order,
      doneOn: status === "done" ? moving.doneOn : null,
      focus: status === "today" ? moving.focus : false,
    };
    let changed: Task[] = [updated];
    // Rare: the neighbours share an order (e.g. hand-written files), so there's no
    // number in between. Then space that whole list out again, once.
    if (prev && next && !(order > prev.order && order < next.order)) {
      list.splice(at, 0, updated);
      changed = list.map((x, i) => ({ ...x, order: (i + 1) * STEP }));
    }
    const map = new Map(changed.map((x) => [x.id, x]));
    setTasks(all.map((x) => map.get(x.id) ?? x));
    setArrived(id);
    changed.forEach(persist);
  }, [persist]);

  /** Order that puts a card on top of `status`. */
  const topOrder = (status: Status) => {
    const orders = tasksRef.current.filter((x) => x.status === status).map((x) => x.order);
    return orders.length ? Math.min(...orders) - STEP : 0;
  };

  /** Ring fills → title strikes → card flies into Done → counter bumps. */
  const complete = useCallback((id: string) => {
    if (completing) return;
    setCompleting(id);
    window.setTimeout(async () => {
      const t = tasksRef.current.find((x) => x.id === id);
      setCompleting(null);
      if (!t) return;
      setTasks((all) => all.map((x) => (x.id === id ? { ...x, status: "done", focus: false, doneOn: nowStamp() } : x)));
      setLastDone(t.title);
      setBump(true);
      window.setTimeout(() => setBump(false), 650);
      lastLocalWrite.current = Date.now();
      try {
        const saved = await api.completeTask(id);
        lastLocalWrite.current = Date.now();
        setTasks((all) => all.map((x) => (x.id === id ? saved : x)));
      } catch (e) {
        setError(String(e));
      }
    }, 880);
  }, [completing]);

  /** New tasks go on top of their list. */
  const add = useCallback(async (title: string, area: string, status: Status) => {
    const tempId = "new-" + Date.now();
    const task: Task = {
      id: tempId, title, area, status, focus: false,
      order: topOrder(status), created: nowStamp(), doneOn: null, items: [], notes: "",
    };
    setTasks((all) => [...all, task]);
    setArrived(tempId);
    await persist({ ...task, id: "" }).then((saved) => {
      setTasks((all) => all.map((x) => (x.id === tempId ? saved : x)));
      setArrived(saved.id);
    });
  }, [persist]);

  /** Renames the file to match a new title. Resolves to the task's new id. */
  const rename = useCallback(async (id: string, title: string): Promise<string> => {
    const t = tasksRef.current.find((x) => x.id === id);
    if (!t || !title.trim() || title.trim() === t.title) return id;
    // Write any pending edit under the old name first.
    const timers = saveTimers.current;
    if (timers.has(id)) { window.clearTimeout(timers.get(id)); timers.delete(id); await persist(t); }
    lastLocalWrite.current = Date.now();
    try {
      const saved = await api.renameTask(id, title.trim(), t.order);
      lastLocalWrite.current = Date.now();
      setTasks((all) => all.map((x) => (x.id === id ? saved : x)));
      return saved.id;
    } catch (e) {
      setError(String(e));
      return id;
    }
  }, [persist]);

  /** A suggested task: accept → top of Backlog (keeps `from:`), dismiss → file deleted. */
  const accept = useCallback((id: string) => patch(id, { status: "backlog", order: topOrder("backlog") }), [patch]);

  const toggleFocus = useCallback((id: string) => {
    const all = tasksRef.current;
    const target = all.find((x) => x.id === id);
    if (!target) return;
    const on = !target.focus;
    all.forEach((x) => {
      if (x.id === id) patch(x.id, { focus: on });
      else if (on && x.focus) patch(x.id, { focus: false }); // only one card in focus
    });
  }, [patch]);

  const cycleColour = useCallback((id: string) => {
    const cats = settings?.categories ?? [];
    const t = tasksRef.current.find((x) => x.id === id);
    if (!t || !cats.length) return;
    const i = cats.findIndex((c) => c.id === t.area);
    patch(id, { area: cats[(i + 1) % cats.length].id });
  }, [settings, patch]);

  // ---------- settings ----------
  const settingsTimer = useRef<number>();
  const updateSettings = useCallback((p: Partial<Settings>, opts: { reloadAfter?: boolean } = {}) => {
    setSettings((s) => {
      if (!s) return s;
      const next = { ...s, ...p };
      window.clearTimeout(settingsTimer.current);
      settingsTimer.current = window.setTimeout(async () => {
        await api.saveSettings(next);
        if (opts.reloadAfter) reload();
      }, 400);
      return next;
    });
  }, [reload]);

  const addCategory = useCallback(() => {
    if (!settings) return;
    const used = settings.categories.map((c) => c.color);
    const color = PALETTE_KEYS.find((k) => !used.includes(k)) ?? "slate";
    let id = slug("category"), n = 2;
    while (settings.categories.some((c) => c.id === id)) id = `category-${n++}`;
    const cat: Category = { id, name: "New category", color };
    updateSettings({ categories: [...settings.categories, cat] });
  }, [settings, updateSettings]);

  /** Removes a category from settings. Task files keep their `area:` value;
   *  until you pick a new category they show in the first one. */
  const removeCategory = useCallback((id: string) => {
    if (!settings || settings.categories.length <= 1) return;
    updateSettings({ categories: settings.categories.filter((c) => c.id !== id) });
  }, [settings, updateSettings]);

  return {
    tasks, settings, error, completing, arrived, bump, lastDone,
    move, complete, add, patch, rename, accept, toggleFocus, cycleColour,
    updateSettings, addCategory, removeCategory,
    remove: async (id: string) => {
      setTasks((all) => all.filter((x) => x.id !== id));
      lastLocalWrite.current = Date.now();
      try { await api.deleteTask(id); } catch (e) { setError(String(e)); }
    },
  };
}

export type Board = ReturnType<typeof useBoard>;
export { byOrder };
