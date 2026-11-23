import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { cleanupFor } from "./api.ts";

/** A subscription that resolves when `ready()` is called, counting unsubscribes. */
const pending = () => {
  let ready!: () => void;
  const sub = { offs: 0, promise: new Promise<() => void>((r) => (ready = () => r(() => sub.offs++))), ready: () => ready() };
  return sub;
};
const tick = () => new Promise((r) => setTimeout(r, 0));

describe("cleanupFor", () => {
  it("unsubscribes every listener once on cleanup", async () => {
    const a = pending(),
      b = pending();
    const cleanup = cleanupFor(a.promise, b.promise);
    a.ready();
    b.ready();
    await tick();
    assert.deepEqual([a.offs, b.offs], [0, 0]);
    cleanup();
    assert.deepEqual([a.offs, b.offs], [1, 1]);
  });

  it("unsubscribes a listener whose subscription resolves after cleanup", async () => {
    const sub = pending();
    const cleanup = cleanupFor(sub.promise);
    cleanup(); // e.g. React Strict Mode unmounting right away
    sub.ready();
    await tick();
    assert.equal(sub.offs, 1);
  });
});
