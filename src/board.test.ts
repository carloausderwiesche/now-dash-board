import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { STEP, planMove, splitFinished, topOrder } from "./board.ts";
import type { Task } from "./types";

const task = (id: string, status: Task["status"], order: number, extra: Partial<Task> = {}): Task => ({
  id,
  title: id,
  status,
  area: "work",
  focus: false,
  order,
  doneOn: null,
  items: [],
  notes: "",
  ...extra,
});

describe("planMove", () => {
  const board = [task("a", "today", 1024), task("b", "today", 2048), task("c", "backlog", 1024)];

  it("puts the card halfway between its new neighbours and changes only that card", () => {
    assert.deepEqual(planMove(board, "c", "today", "b"), [{ ...board[2], status: "today", order: 1536 }]);
  });

  it("goes one step above the first card or below the last", () => {
    assert.equal(planMove(board, "c", "today", "a")[0].order, 1024 - STEP);
    assert.equal(planMove(board, "c", "today")[0].order, 2048 + STEP);
  });

  it("gets order 0 in an empty list", () => {
    assert.equal(planMove(board, "a", "suggested")[0].order, 0);
  });

  it("ends focus outside Today and clears the done time outside Done", () => {
    const focused = task("f", "today", 1, { focus: true });
    assert.equal(planMove([focused], "f", "backlog")[0].focus, false);
    const done = task("d", "done", 1, { doneOn: "2026-11-22T09:40" });
    assert.equal(planMove([done], "d", "today")[0].doneOn, null);
    assert.equal(planMove([done, task("e", "done", 5)], "d", "done")[0].doneOn, "2026-11-22T09:40");
  });

  it("spaces the whole list out again when the neighbours share an order", () => {
    const tied = [task("a", "today", 7), task("b", "today", 7), task("c", "backlog", 1)];
    const changed = planMove(tied, "c", "today", "b");
    assert.deepEqual(
      changed.map((t) => [t.id, t.order]),
      [
        ["a", STEP],
        ["c", 2 * STEP],
        ["b", 3 * STEP],
      ],
    );
  });

  it("changes nothing for an unknown card or a drop onto itself", () => {
    assert.deepEqual(planMove(board, "nope", "today"), []);
    assert.deepEqual(planMove(board, "a", "today", "a"), []);
  });
});

describe("topOrder", () => {
  it("is one step above the smallest order in the list, or 0 when empty", () => {
    assert.equal(topOrder([task("a", "today", 300), task("b", "today", 100)], "today"), 100 - STEP);
    assert.equal(topOrder([task("a", "today", 300)], "backlog"), 0);
  });
});

describe("splitFinished", () => {
  it("keeps a card finished on disk as it is on screen and reports it", () => {
    const shown = [task("a", "today", 1)];
    const doneOnDisk = task("a", "done", 1, { doneOn: "2026-11-22T10:00" });
    assert.deepEqual(splitFinished(shown, [doneOnDisk]), { tasks: shown, finished: [doneOnDisk] });
  });

  it("takes everything else straight from disk", () => {
    const shown = [task("a", "done", 1), task("b", "today", 1, { title: "Old" })];
    const fresh = [task("a", "done", 1), task("b", "today", 1, { title: "New" }), task("c", "done", 1)];
    assert.deepEqual(splitFinished(shown, fresh), { tasks: fresh, finished: [] });
  });
});
