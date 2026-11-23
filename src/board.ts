// Pure board logic: no React, no disk. Kept apart from useBoard so it can be
// tested on its own (board.test.ts).

import type { Status, Task } from "./types";

export const todayStr = () => new Date().toLocaleDateString("sv-SE"); // YYYY-MM-DD, local time
/** Local time as "2026-11-22T09:40", the format of `created:` and `done:`. */
export const nowStamp = () => {
  const d = new Date(),
    pad = (n: number) => String(n).padStart(2, "0");
  return `${todayStr()}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

export const STEP = 1024; // gap between orders: new tasks go 1024 above the top one
export const byOrder = (a: Task, b: Task) => a.order - b.order || a.title.localeCompare(b.title);

/** Order that puts a card on top of `status`. */
export const topOrder = (all: Task[], status: Status) => {
  const orders = all.filter((x) => x.status === status).map((x) => x.order);
  return orders.length ? Math.min(...orders) - STEP : 0;
};

/** Moves a card into `status`, before `beforeId` or at the end, and returns
 *  every task that changed (usually just the moved one), or [] if nothing moves.
 *  Fractional ordering: the card gets the midpoint of its two neighbours'
 *  orders, so only this one file is rewritten. */
export function planMove(all: Task[], id: string, status: Status, beforeId?: string): Task[] {
  const moving = all.find((x) => x.id === id);
  if (!moving || id === beforeId) return [];
  const list = all.filter((x) => x.status === status && x.id !== id).sort(byOrder);
  let at = beforeId ? list.findIndex((x) => x.id === beforeId) : list.length;
  if (at < 0) at = list.length;
  const prev = list[at - 1],
    next = list[at];
  const order = prev && next ? (prev.order + next.order) / 2 : next ? next.order - STEP : prev ? prev.order + STEP : 0;
  const updated: Task = {
    ...moving,
    status,
    order,
    doneOn: status === "done" ? moving.doneOn : null,
    focus: status === "today" ? moving.focus : false,
  };
  // Rare: the neighbours share an order (e.g. hand-written files), so there's no
  // number in between. Then space that whole list out again, once.
  if (prev && next && !(order > prev.order && order < next.order)) {
    list.splice(at, 0, updated);
    return list.map((x, i) => ({ ...x, order: (i + 1) * STEP }));
  }
  return [updated];
}

/** Compares a fresh load from disk with what's on screen. Cards someone else
 *  (Obsidian, an agent) just marked done keep their on-screen version for now
 *  and come back in `finished`, so the app can animate them first. */
export function splitFinished(shown: Task[], fresh: Task[]): { tasks: Task[]; finished: Task[] } {
  const before = new Map(shown.map((x) => [x.id, x]));
  const finished: Task[] = [];
  const tasks = fresh.map((x) => {
    const old = before.get(x.id);
    if (x.status !== "done" || !old || old.status === "done") return x;
    finished.push(x);
    return old;
  });
  return { tasks, finished };
}
