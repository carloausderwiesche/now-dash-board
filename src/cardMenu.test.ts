import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { cardMenu, placeMenu, type CardActions, type CardMenuModel } from "./cardMenu.ts";
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
    remove: () => calls.push("remove"),
  };
  return { calls, act };
};
const texts = (m: CardMenuModel) => m.groups.map((g) => g.map((i) => i.text));
const click = (m: CardMenuModel, text: string) => {
  const item = m.groups.flat().find((i) => i.text === text);
  assert.ok(item, `no "${text}" in ${JSON.stringify(texts(m))}`);
  item.action();
};

describe("cardMenu", () => {
  it("offers focus and moving back to Backlog for a Today card", () => {
    const { calls, act } = recorder();
    const menu = cardMenu(task("today"), categories, act);
    assert.deepEqual(texts(menu), [["Open", "Move to Backlog", "Focus on this now", "Mark done"], ["Open in Obsidian"], ["Delete file…"]]);
    click(menu, "Move to Backlog");
    click(menu, "Focus on this now");
    assert.deepEqual(calls, ["move backlog", "focus"]);
  });

  it("offers Today and no focus for a Backlog card", () => {
    const { calls, act } = recorder();
    const menu = cardMenu(task("backlog"), categories, act);
    assert.deepEqual(texts(menu)[0], ["Open", "Move to Today", "Mark done"]);
    click(menu, "Move to Today");
    assert.deepEqual(calls, ["move today"]);
  });

  it("marks the card's category as current and switches to the one clicked", () => {
    const { calls, act } = recorder();
    const menu = cardMenu(task("today"), categories, act);
    assert.deepEqual(
      menu.categories.map((c) => [c.name, c.current]),
      [
        ["Work", true],
        ["Personal", false],
      ],
    );
    menu.categories[1].action();
    assert.deepEqual(calls, ["category personal"]);
  });

  it("puts Delete last, on its own, behind a confirmation", () => {
    const menu = cardMenu(task("today"), categories, recorder().act);
    const last = menu.groups.at(-1)!;
    assert.equal(last.length, 1);
    assert.equal(last[0].text, "Delete file…");
    assert.ok(last[0].confirm);
    assert.ok(
      menu.groups
        .slice(0, -1)
        .flat()
        .every((i) => !i.confirm),
    );
  });
});

describe("placeMenu", () => {
  const menu = { w: 240, h: 300 },
    win = { w: 1000, h: 800 };

  it("opens down and right of the pointer when there is room", () => {
    assert.deepEqual(placeMenu({ x: 100, y: 100 }, menu, win), { x: 100, y: 100 });
  });

  it("flips up and left near the bottom-right corner", () => {
    assert.deepEqual(placeMenu({ x: 900, y: 700 }, menu, win), { x: 660, y: 400 });
  });

  it("stays inside a window too small to flip into", () => {
    assert.deepEqual(placeMenu({ x: 100, y: 150 }, menu, { w: 1000, h: 320 }), { x: 100, y: 8 });
  });
});
