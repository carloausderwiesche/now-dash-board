// Makes cards glide to their new spot instead of jumping when the list changes
// (a card completes, moves, a drag preview opens a gap…). This is the "FLIP"
// trick: remember where every card was, and after React re-renders, start each
// moved card at its old spot and animate it to the new one.

import { useLayoutEffect, useRef } from "react";

type Pos = { x: number; y: number };
const running = new WeakMap<HTMLElement, Animation>(); // our own slide per card (not the CSS ones)

export function useFlip<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const last = useRef(new Map<string, Pos>());

  // No dependency list on purpose: this runs after every render, before paint.
  useLayoutEffect(() => {
    const box = ref.current;
    if (!box) return;
    const origin = box.getBoundingClientRect(); // relative to the grid, so scrolling doesn't count as movement
    const at = (el: HTMLElement): Pos => {
      const r = el.getBoundingClientRect();
      return { x: r.left - origin.left, y: r.top - origin.top };
    };
    const next = new Map<string, Pos>();
    box.querySelectorAll<HTMLElement>("[data-flip]").forEach((el) => {
      if (el.offsetParent === null) return; // hidden (the card you're dragging)
      const key = el.dataset.flip!;
      // If the card is still sliding from a previous change, start the new slide
      // from where it is *on screen* right now, so it never snaps.
      const sliding = running.get(el);
      let prev = last.current.get(key);
      if (sliding && sliding.playState === "running") {
        prev = at(el);
        sliding.cancel();
      }
      const pos = at(el); // its real place in the layout
      next.set(key, pos);
      // The drop preview stands in for the dragged card: after the drop, the
      // real card starts where the preview was, so it doesn't fly across.
      if (el.dataset.ghostFor) next.set(el.dataset.ghostFor, pos);
      if (!prev || el.classList.contains("completing")) return;
      const dx = prev.x - pos.x, dy = prev.y - pos.y;
      if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return;
      running.set(el, el.animate(
        [{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }],
        { duration: 420, easing: "cubic-bezier(.25, .8, .25, 1)" }, // calm ease-out, no overshoot
      ));
    });
    last.current = next;
  });

  return ref;
}
