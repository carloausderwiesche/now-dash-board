// All board state and every action (move, complete, edit…) in one hook.
// Pattern: update React state first (instant UI), then write the file.
// The pure logic lives in board.ts, settings in useSettings, the "done"
// animation in useCompletion.

import { useCallback, useEffect, useRef, useState } from "react";
import { api, cleanupFor } from "./api";
import { nowStamp, planMove, splitFinished, topOrder } from "./board";
import { useCompletion } from "./useCompletion";
import { useSettings } from "./useSettings";
import type { Status, Task } from "./types";

const TYPING_SAVE_MS = 500; // text edits are saved this long after you stop typing
const OWN_WRITE_ECHO_MS = 1200; // file events this soon after our own write are our own echo
const RELOAD_DEBOUNCE_MS = 200; // one reload for a burst of file events

export function useBoard() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [arrived, setArrived] = useState<string | null>(null);
  const done = useCompletion();

  const tasksRef = useRef<Task[]>([]);
  tasksRef.current = tasks;
  const lastLocalWrite = useRef(0);
  const saveTimers = useRef(new Map<string, number>());

  // ---------- loading ----------
  const { queue } = done;
  const reload = useCallback(async () => {
    try {
      const { tasks: shown, finished } = splitFinished(tasksRef.current, await api.listTasks());
      setTasks(shown);
      queue(finished);
    } catch (e) {
      setError(String(e));
      setTasks([]);
    }
  }, [queue]);

  const { settings, updateSettings, addCategory, removeCategory } = useSettings(reload);

  useEffect(() => {
    reload();
    let t: number | undefined;
    const stop = cleanupFor(
      api.onTasksChanged(() => {
        // Ignore the echo of our own writes, and never reload mid-typing.
        if (Date.now() - lastLocalWrite.current < OWN_WRITE_ECHO_MS || saveTimers.current.size > 0) return;
        window.clearTimeout(t);
        t = window.setTimeout(reload, RELOAD_DEBOUNCE_MS);
      }),
    );
    return () => {
      stop();
      window.clearTimeout(t);
    };
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

  const persistSoon = useCallback(
    (task: Task) => {
      const timers = saveTimers.current;
      window.clearTimeout(timers.get(task.id));
      timers.set(
        task.id,
        window.setTimeout(() => {
          timers.delete(task.id);
          const latest = tasksRef.current.find((x) => x.id === task.id);
          if (latest) persist(latest);
        }, TYPING_SAVE_MS),
      );
    },
    [persist],
  );

  /** Drops a pending text-edit save. Returns true if there was one. */
  const cancelPendingSave = useCallback((id: string) => {
    const timers = saveTimers.current;
    if (!timers.has(id)) return false;
    window.clearTimeout(timers.get(id));
    timers.delete(id);
    return true;
  }, []);

  const patch = useCallback(
    (id: string, p: Partial<Task>, opts: { soon?: boolean } = {}) => {
      const current = tasksRef.current.find((x) => x.id === id);
      if (!current) return;
      const next = { ...current, ...p };
      setTasks((all) => all.map((x) => (x.id === id ? next : x)));
      if (opts.soon) persistSoon(next);
      else persist(next);
    },
    [persist, persistSoon],
  );

  /** `quiet`: no pop-in animation (a drag-and-drop already showed where it lands). */
  const move = useCallback(
    (id: string, status: Status, beforeId?: string, opts: { quiet?: boolean } = {}) => {
      const changed = planMove(tasksRef.current, id, status, beforeId);
      if (!changed.length) return;
      const map = new Map(changed.map((x) => [x.id, x]));
      setTasks((all) => all.map((x) => map.get(x.id) ?? x));
      setArrived(opts.quiet ? null : id);
      changed.forEach(persist);
    },
    [persist],
  );

  const { completing, forget, play } = done;
  const complete = useCallback(
    (id: string) => {
      if (completing) return;
      // Already done (a second file event while it was animating): nothing to play.
      if (tasksRef.current.find((x) => x.id === id)?.status === "done") return forget(id);
      play(id, (onDisk) => {
        const t = tasksRef.current.find((x) => x.id === id);
        if (!t) return null;
        if (onDisk) {
          // Finished on disk: just show the file's version, no write.
          setTasks((all) => all.map((x) => (x.id === id ? onDisk : x)));
          return onDisk.title;
        }
        setTasks((all) => all.map((x) => (x.id === id ? { ...x, status: "done", focus: false, doneOn: nowStamp() } : x)));
        lastLocalWrite.current = Date.now();
        api.completeTask(id).then(
          (saved) => {
            lastLocalWrite.current = Date.now();
            setTasks((all) => all.map((x) => (x.id === id ? saved : x)));
          },
          (e) => setError(String(e)),
        );
        return t.title;
      });
    },
    [completing, forget, play],
  );

  /** New tasks go on top of their list. */
  const add = useCallback(
    async (title: string, area: string, status: Status) => {
      const tempId = "new-" + Date.now();
      const task: Task = {
        id: tempId,
        title,
        area,
        status,
        focus: false,
        order: topOrder(tasksRef.current, status),
        created: nowStamp(),
        doneOn: null,
        items: [],
        notes: "",
      };
      setTasks((all) => [...all, task]);
      setArrived(tempId);
      const saved = await persist({ ...task, id: "" });
      setTasks((all) => all.map((x) => (x.id === tempId ? saved : x)));
      setArrived(saved.id);
    },
    [persist],
  );

  /** Renames the file to match a new title. Resolves to the task's new id. */
  const rename = useCallback(
    async (id: string, title: string): Promise<string> => {
      const t = tasksRef.current.find((x) => x.id === id);
      if (!t || !title.trim() || title.trim() === t.title) return id;
      // Write any pending edit under the old name first.
      if (cancelPendingSave(id)) await persist(t);
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
    },
    [persist, cancelPendingSave],
  );

  /** Deletes the task's file. A pending edit is dropped first, or it would write the file back. */
  const remove = useCallback(
    async (id: string) => {
      cancelPendingSave(id);
      setTasks((all) => all.filter((x) => x.id !== id));
      lastLocalWrite.current = Date.now();
      try {
        await api.deleteTask(id);
      } catch (e) {
        setError(String(e));
      }
    },
    [cancelPendingSave],
  );

  /** A suggested task: accept → top of Backlog (keeps `from:`), dismiss → file deleted. */
  const accept = useCallback((id: string) => patch(id, { status: "backlog", order: topOrder(tasksRef.current, "backlog") }), [patch]);

  const toggleFocus = useCallback(
    (id: string) => {
      const target = tasksRef.current.find((x) => x.id === id);
      if (!target) return;
      const on = !target.focus;
      tasksRef.current.forEach((x) => {
        if (x.id === id) patch(x.id, { focus: on });
        else if (on && x.focus) patch(x.id, { focus: false }); // only one card in focus
      });
    },
    [patch],
  );

  const cycleColour = useCallback(
    (id: string) => {
      const cats = settings?.categories ?? [];
      const t = tasksRef.current.find((x) => x.id === id);
      if (!t || !cats.length) return;
      const i = cats.findIndex((c) => c.id === t.area);
      patch(id, { area: cats[(i + 1) % cats.length].id });
    },
    [settings, patch],
  );

  return {
    tasks,
    settings,
    error,
    arrived,
    completing,
    bump: done.bump,
    lastDone: done.lastDone,
    /** Ids finished outside the app, oldest first, waiting to be animated. */
    incoming: done.incoming,
    move,
    complete,
    add,
    patch,
    rename,
    remove,
    accept,
    toggleFocus,
    cycleColour,
    updateSettings,
    addCategory,
    removeCategory,
  };
}

export type Board = ReturnType<typeof useBoard>;
