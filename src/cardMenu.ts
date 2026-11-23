// What right-clicking a card offers. Pure: api.contextMenu turns it into a
// native macOS menu, so this can be tested without Tauri.

import type { Category, Status, Task } from "./types";

export type MenuEntry = { text: string; action?: () => void; checked?: boolean; items?: MenuEntry[] } | "separator";

export interface CardActions {
  open(): void;
  move(status: Status): void;
  finish(): void;
  toggleFocus(): void;
  setCategory(id: string): void;
  openInObsidian(): void;
}

/** No Delete here on purpose: one slip in a menu would remove the file. Delete stays in the detail panel. */
export function cardMenu(task: Task, categories: Category[], act: CardActions): MenuEntry[] {
  const today = task.status === "today";
  return [
    { text: "Open", action: act.open },
    today ? { text: "Move to Backlog", action: () => act.move("backlog") } : { text: "Move to Today", action: () => act.move("today") },
    ...(today ? [{ text: task.focus ? "Stop focusing on this" : "Focus on this now", action: act.toggleFocus }] : []),
    { text: "Mark done", action: act.finish },
    "separator",
    {
      text: "Category",
      items: categories.map((c) => ({ text: c.name, checked: c.id === task.area, action: () => act.setCategory(c.id) })),
    },
    "separator",
    { text: "Open in Obsidian", action: act.openInObsidian },
  ];
}
