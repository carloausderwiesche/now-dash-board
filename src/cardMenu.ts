// What right-clicking a card offers, and where the menu goes. Pure, so it can
// be tested without a browser; components/CardMenu.tsx draws it.

import type { Category, Status, Task } from "./types";

export type MenuIcon = "up" | "down" | "focus" | "pause" | "done" | "external" | "trash";
export interface MenuItem {
  text: string;
  icon?: MenuIcon;
  action: () => void;
  /** Needs a second click, showing this text, before `action` runs. */
  confirm?: string;
}
export interface CardMenuModel {
  categories: { id: string; name: string; current: boolean; action: () => void }[];
  /** Shown with a divider between groups. */
  groups: MenuItem[][];
}

export interface CardActions {
  open(): void;
  move(status: Status): void;
  finish(): void;
  toggleFocus(): void;
  setCategory(id: string): void;
  openInObsidian(): void;
  remove(): void;
}

export function cardMenu(task: Task, categories: Category[], act: CardActions): CardMenuModel {
  const today = task.status === "today";
  return {
    categories: categories.map((c) => ({ id: c.id, name: c.name, current: c.id === task.area, action: () => act.setCategory(c.id) })),
    groups: [
      [
        { text: "Open", action: act.open },
        today
          ? { text: "Move to Backlog", icon: "down", action: () => act.move("backlog") }
          : { text: "Move to Today", icon: "up", action: () => act.move("today") },
        ...(today
          ? [
              task.focus
                ? { text: "Stop focusing", icon: "pause" as const, action: act.toggleFocus }
                : { text: "Focus on this now", icon: "focus" as const, action: act.toggleFocus },
            ]
          : []),
        { text: "Mark done", icon: "done", action: act.finish },
      ],
      [{ text: "Open in Obsidian", icon: "external", action: act.openInObsidian }],
      [{ text: "Delete file…", icon: "trash", action: act.remove, confirm: "Click again to delete" }],
    ],
  };
}

const EDGE = 8; // keep this far from the window edges

/** Top-left corner for a menu opened at the pointer: down and right of it,
 *  flipped up or left when it wouldn't fit, and never off-screen. */
export function placeMenu(at: { x: number; y: number }, menu: { w: number; h: number }, win: { w: number; h: number }) {
  const x = at.x + menu.w + EDGE <= win.w ? at.x : at.x - menu.w;
  const y = at.y + menu.h + EDGE <= win.h ? at.y : at.y - menu.h;
  return {
    x: Math.max(EDGE, Math.min(x, win.w - menu.w - EDGE)),
    y: Math.max(EDGE, Math.min(y, win.h - menu.h - EDGE)),
  };
}
