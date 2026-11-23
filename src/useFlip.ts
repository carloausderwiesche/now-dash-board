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
    // Where the card sits in the grid's layout. offsetLeft/offsetTop ignore CSS
    // transforms, so the hover lift (and the lift of the card whose panel is open)
    // doesn't count as "moving". Measuring on-screen boxes instead made a card dip
    // and bounce back whenever it gained or lost that 3px lift. (The grid is
    // position: relative, so offsets are measured from it and scrolling doesn't count.)
    const at = (el: HTMLElement): Pos => ({ x: el.offsetLeft, y: el.offsetTop });
    const next = new Map<string, Pos>();
    box.querySelectorAll<HTMLElement>("[data-flip]").forEach((el) => {
      if (el.offsetParent === null) return; // hidden (the card you're dragging)
      const key = el.dataset.flip!;
      const pos = at(el); // its real place in the layout
      let prev = last.current.get(key);
      // If the card is still sliding from a previous change, start the new slide
      // from where it is *on screen* right now, so it never snaps. The slide's
      // current offset = the box with the slide minus the box without it.
      const sliding = running.get(el);
      if (sliding && sliding.playState === "running") {
        const a = el.getBoundingClientRect();
        sliding.cancel();
        const b = el.getBoundingClientRect();
        prev = { x: pos.x + a.left - b.left, y: pos.y + a.top - b.top };
      }
      next.set(key, pos);
      // The drop preview stands in for the dragged card: after the drop, the
      // real card starts where the preview was, so it doesn't fly across.
      if (el.dataset.ghostFor) next.set(el.dataset.ghostFor, pos);
      if (!prev || el.classList.contains("completing")) return;
      const dx = prev.x - pos.x,
        dy = prev.y - pos.y;
      if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return;
      running.set(
        el,
        el.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "translate(0, 0)" }], {
          duration: 420,
          easing: "cubic-bezier(.25, .8, .25, 1)", // calm ease-out, no overshoot
          // "add": the slide goes on top of the card's own transform (e.g. the hover
          // lift), so a hovered card stays lifted while it moves instead of dipping
          // down and popping back up at the end.
          composite: "add",
        }),
      );
    });
    last.current = next;
  });

  return ref;
}
