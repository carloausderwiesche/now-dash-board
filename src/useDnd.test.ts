import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { dropPreview } from "./useDnd.ts";

describe("dropPreview", () => {
  const list = ["a", "b", "c"];

  it("shows nothing while the card points at its own slot", () => {
    assert.equal(dropPreview(list, "b", "b"), null);
    assert.equal(dropPreview(list, "b", "c"), null); // just below itself is the same spot
    assert.equal(dropPreview(list, "c"), null); // the last card dragged to the end
  });

  it("closes the card's own slot when it moves elsewhere in its list", () => {
    assert.deepEqual(dropPreview(list, "c", "a"), { index: 0, collapse: true });
    assert.deepEqual(dropPreview(list, "a"), { index: 3, collapse: true });
  });

  it("only opens a gap when the card comes from another list", () => {
    assert.deepEqual(dropPreview(list, "x", "b"), { index: 1, collapse: false });
    assert.deepEqual(dropPreview([], "x"), { index: 0, collapse: false });
  });

  it("shows nothing for a card that isn't in the list", () => {
    assert.equal(dropPreview(list, "x", "gone"), null);
  });
});
