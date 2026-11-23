import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { cardMenu, type CardActions, type MenuEntry } from "./cardMenu.ts";
import type { Task } from "./types";

const task = (status: Task["status"], extra: Partial<Task> = {}): Task => ({
  id: "a.md",
  title: "a",
  status,
  area: "work",
  focus: false,
  order: 1024,
  doneOn: null,
  items: [],
  notes: "",
  ...extra,
});
const categories = [
  { id: "work", name: "Work", color: "blue" as const },
  { id: "personal", name: "Personal", color: "rose" as const },
];

/** Records which action each click runs. */
const recorder = () => {
  const calls: string[] = [];
  const act: CardActions = {
    open: () => calls.push("open"),
    move: (s) => calls.push("move " + s),
    finish: () => calls.push("finish"),
    toggleFocus: () => calls.push("focus"),
    setCategory: (id) => calls.push("category " + id),
    openInObsidian: () => calls.push("obsidian"),
  };
  return { calls, act };
};
const texts = (menu: MenuEntry[]) => menu.map((e) => (e === "separator" ? "—" : e.text));
const click = (menu: MenuEntry[], text: string) => {
  const entry = menu.find((e) => e !== "separator" && e.text === text);
  assert.ok(entry && entry !== "separator" && entry.action, `no clickable "${text}" in ${texts(menu)}`);
  entry.action();
};

describe("cardMenu", () => {
  it("offers focus and moving back to Backlog for a Today card", () => {
    const { calls, act } = recorder();
    const menu = cardMenu(task("today"), categories, act);
    assert.deepEqual(texts(menu), ["Open", "Move to Backlog", "Focus on this now", "Mark done", "—", "Category", "—", "Open in Obsidian"]);
    click(menu, "Move to Backlog");
    click(menu, "Focus on this now");
    assert.deepEqual(calls, ["move backlog", "focus"]);
  });

  it("offers Today and no focus for a Backlog card", () => {
    const { calls, act } = recorder();
    const menu = cardMenu(task("backlog"), categories, act);
    assert.ok(!texts(menu).some((t) => t.includes("ocus")));
    click(menu, "Move to Today");
    assert.deepEqual(calls, ["move today"]);
  });

  it("ticks the card's category and switches to the one clicked", () => {
    const { calls, act } = recorder();
    const sub = cardMenu(task("today"), categories, act).find((e) => e !== "separator" && e.text === "Category");
    assert.ok(sub && sub !== "separator" && sub.items);
    assert.deepEqual(
      sub.items.map((e) => e !== "separator" && [e.text, e.checked]),
      [
        ["Work", true],
        ["Personal", false],
      ],
    );
    click(sub.items, "Personal");
    assert.deepEqual(calls, ["category personal"]);
  });

  it("never offers Delete", () => {
    const menu = cardMenu(task("today", { focus: true }), categories, recorder().act);
    assert.ok(!texts(menu).some((t) => /delete/i.test(t)));
  });
});
