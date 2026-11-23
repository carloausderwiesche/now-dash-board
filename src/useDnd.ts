// Drag and drop for cards: Today, Backlog, Done.
//
// Built on plain pointer events, not the browser's HTML5 drag and drop. In the
// macOS app the built-in kind goes through the system drag session, which shows
// a "+ copy" cursor for a moment and leaves stale hover states behind. Here a
// copy of the card simply follows the pointer, and the cursor stays a closed hand.
//
// `over` is where the card would land; `preview` tells App where to render a
// faded "ghost" there, and `zoneClass` tints that section. Rules, so it feels calm:
//  - A press only becomes a drag after the pointer moves a few pixels, so
//    clicks on a card (title, dot, check) work as before.
//  - Picking a card up changes nothing: its own slot is the preview.
//  - The drop areas follow each other with no gaps: a list's area runs from its
//    cards down to where the next list's cards start (so the next list's heading
//    still counts as the list above). From Backlog, a short drag up reaches Today.
//  - Inside an area, the spot is the grid cell under the pointer: the preview
//    goes exactly where you point, and past the last card means "at the end".
//  - A new spot is only taken once the pointer has rested on it briefly.
//  - Above the board (the header) the preview stays where it last was, and
//    letting go there uses that spot. Esc cancels.
//
// App marks the pieces with data attributes: each section has
// data-section="today|backlog|done", each card grid data-grid.

import { useRef, useState, type PointerEvent } from "react";
import type { Status } from "./types";

export type DropTarget = { status: Status; beforeId?: string };

const SETTLE_MS = 70; // pointer must rest this long on a new spot before the preview moves
const same = (a: DropTarget | null, b: DropTarget | null) => a?.status === b?.status && a?.beforeId === b?.beforeId;

/**
 * Which list's drop area is at height `y`, and that list's card grid (if any).
 * The areas follow each other with no gaps: each one starts where its cards
 * start and runs until the next list's cards start. So the space under Today,
 * the Suggested strip and the Backlog *heading* all count as Today: dragging a
 * Backlog card up just past its row is enough to land in Today.
 */
function zoneAt(y: number): { status: Status; grid: HTMLElement | null } | null {
  const sections = Array.from(document.querySelectorAll<HTMLElement>("[data-section]"));
  // Where each area starts: the first one at its heading, the others at their cards
  // (Done at its heading, which is itself the drop target).
  const tops = sections.map((s, i) => {
    const grid = s.querySelector<HTMLElement>("[data-grid]");
    return i === 0 || !grid ? s.getBoundingClientRect().top : grid.getBoundingClientRect().top - 8;
  });
  for (let i = 0; i < sections.length; i++) {
    const bottom = i + 1 < sections.length ? tops[i + 1] : sections[i].getBoundingClientRect().bottom + 120;
    if (y >= tops[i] && y < bottom) {
      return { status: sections[i].dataset.section as Status, grid: sections[i].querySelector<HTMLElement>("[data-grid]") };
    }
  }
  return null;
}

/** How many grid columns an element spans (the focus card spans 2). */
const spanOf = (el: Element, cols: number) => {
  const st = getComputedStyle(el); // `grid-column: span 2` ends up on the start side
  const m = /span (\d+)/.exec(`${st.gridColumnStart} ${st.gridColumnEnd}`);
  return Math.min(m ? Number(m[1]) : 1, cols);
};

/**
 * The drop spot inside a grid, from the pointer position. null = keep the current one.
 *
 * Works in grid *cells*: find the cell under the pointer, then pick the position
 * at which the preview itself would sit in exactly that cell. Because the
 * preview then lands under the pointer, the next check gives the same answer,
 * so it can't flip back and forth (which "nearest card" did at row ends).
 */
function spotIn(grid: HTMLElement | null, status: Status, x: number, y: number, draggedId: string): DropTarget | null {
  if (!grid || status === "done") return { status };
  const cs = getComputedStyle(grid);
  const widths = cs.gridTemplateColumns
    .split(" ")
    .map(parseFloat)
    .filter((n) => !Number.isNaN(n));
  const cols = Math.max(1, widths.length);
  const colGap = parseFloat(cs.columnGap) || 0,
    rowGap = parseFloat(cs.rowGap) || 0;
  const o = grid.getBoundingClientRect();
  const px = x - o.left,
    py = y - o.top;

  // Column under the pointer (each column owns half the gap on either side).
  let col = cols - 1;
  for (let i = 0, left = 0; i < cols; left += widths[i] + colGap, i++) {
    if (px < left + widths[i] + colGap / 2) {
      col = i;
      break;
    }
  }
  // Row under the pointer, from where the visible cards sit (offsetTop ignores slide animations).
  const shown = Array.from(grid.querySelectorAll<HTMLElement>(":scope > [data-flip]")).filter((el) => el.offsetParent !== null);
  const bottoms = new Map<number, number>();
  for (const el of shown) bottoms.set(el.offsetTop, Math.max(bottoms.get(el.offsetTop) ?? 0, el.offsetTop + el.offsetHeight));
  const rowBottoms = Array.from(bottoms.keys())
    .sort((a, b) => a - b)
    .map((t) => bottoms.get(t)!);
  let row = rowBottoms.findIndex((b) => py < b + rowGap / 2);
  if (row < 0) row = rowBottoms.length; // below the last row
  const cell = row * cols + col;

  // The list without the dragged card and without the preview, in order.
  const rest = Array.from(grid.querySelectorAll<HTMLElement>(":scope > [data-flip]")).filter(
    (el) => !el.dataset.ghostFor && el.dataset.flip !== draggedId,
  );
  const spans = rest.map((el) => spanOf(el, cols));
  const dragged = document.querySelector(`[data-flip="${CSS.escape(draggedId)}"]`);
  const ghostSpan = status === "today" && dragged?.classList.contains("is-focus") ? Math.min(2, cols) : 1;

  // Lay the cards out like CSS grid does, with the preview at position p,
  // and return the cell where the preview starts.
  const previewCell = (p: number) => {
    let r = 0,
      c = 0;
    const place = (span: number) => {
      if (span > cols - c) {
        r++;
        c = 0;
      } // doesn't fit: next row
      const start = r * cols + c;
      c += span;
      if (c >= cols) {
        r++;
        c = 0;
      }
      return start;
    };
    for (let i = 0; i < p; i++) place(spans[i]);
    return place(ghostSpan);
  };
  for (let p = 0; p <= rest.length; p++) {
    const start = previewCell(p);
    if (cell >= start && cell < start + ghostSpan) return { status, beforeId: rest[p]?.dataset.flip };
  }
  // Past the last card: at the end. Otherwise (a gap left by a wide card): keep.
  return cell > previewCell(rest.length) ? { status } : null;
}

/**
 * Where the drop preview goes in one list (`ids` = its cards in order), or null
 * for none. While dragging inside one list, the card's own slot *is* the
 * preview (it just fades), so nothing moves until you point somewhere else.
 * Then that slot closes (`collapse`) and the preview opens at `index`: only the
 * cards in between shift, by one place.
 */
export function dropPreview(ids: string[], draggedId: string, beforeId?: string): { index: number; collapse: boolean } | null {
  const at = beforeId ? ids.indexOf(beforeId) : ids.length;
  const from = ids.indexOf(draggedId);
  if (at < 0 || (from >= 0 && (at === from || at === from + 1))) return null;
  return { index: at, collapse: from >= 0 };
}

const START_PX = 5; // movement needed before a press becomes a drag
const EDGE_PX = 48; // near the window's top/bottom edge the page scrolls while dragging

export function useDnd(onDrop: (id: string, target: DropTarget) => void) {
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOverState] = useState<DropTarget | null>(null);
  const overRef = useRef<DropTarget | null>(null);
  const pending = useRef<{ t: DropTarget; since: number } | null>(null);
  // The card you just dropped stays still (no hover lift) until the mouse leaves it.
  const [landed, setLanded] = useState<string | null>(null);
  const onDropRef = useRef(onDrop);
  onDropRef.current = onDrop;

  const commit = (t: DropTarget | null) => {
    pending.current = null;
    if (same(overRef.current, t)) return;
    overRef.current = t;
    setOverState(t);
  };
  /** Moves the preview to `t`, but only once the pointer has settled there. */
  const propose = (t: DropTarget) => {
    if (same(overRef.current, t)) {
      pending.current = null;
      return;
    }
    const now = performance.now(),
      p = pending.current;
    if (p && same(p.t, t)) {
      if (now - p.since >= SETTLE_MS) commit(t);
    } else pending.current = { t, since: now };
  };

  /** Props for a draggable card. */
  const card = (id: string, status: Status) => ({
    onMouseLeave: () => setLanded((l) => (l === id ? null : l)),
    onPointerDown: (e: PointerEvent) => {
      if (e.button !== 0 || e.pointerType === "touch") return; // touch keeps scrolling the page
      const el = e.currentTarget as HTMLElement;
      const sx = e.clientX,
        sy = e.clientY;
      let clone: HTMLElement | null = null;
      let last = { x: sx, y: sy };
      let raf = 0;

      const begin = () => {
        // A copy of the card that follows the pointer.
        const r = el.getBoundingClientRect();
        clone = el.cloneNode(true) as HTMLElement;
        clone.removeAttribute("data-flip");
        clone.classList.remove("dragging", "landed", "arrive");
        clone.classList.add("drag-clone");
        Object.assign(clone.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
        document.body.appendChild(clone);
        document.documentElement.classList.add("grabbing");
        commit({ status, beforeId: id }); // the card's own slot: nothing moves yet
        setDragging(id);
        tick();
      };
      // Every frame: keep the preview up to date and scroll near the edges.
      const tick = () => {
        raf = requestAnimationFrame(tick);
        const { x, y } = last;
        if (y < EDGE_PX) window.scrollBy(0, -Math.ceil((EDGE_PX - y) / 4));
        else if (y > window.innerHeight - EDGE_PX) window.scrollBy(0, Math.ceil((y - window.innerHeight + EDGE_PX) / 4));
        const zone = zoneAt(y);
        if (!zone) return; // heading, header, margins: keep the last spot
        const t = spotIn(zone.grid, zone.status, x, y, id);
        if (t) propose(t);
      };
      const move = (ev: globalThis.PointerEvent) => {
        last = { x: ev.clientX, y: ev.clientY };
        if (!clone) {
          if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < START_PX) return;
          begin();
        }
        ev.preventDefault(); // no text selection while dragging
        clone!.style.transform = `translate(${ev.clientX - sx}px, ${ev.clientY - sy}px)`;
      };
      const end = (drop: boolean) => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
        window.removeEventListener("keydown", key);
        cancelAnimationFrame(raf);
        if (!clone) return; // it was just a click
        clone.remove();
        document.documentElement.classList.remove("grabbing");
        // The click that ends a drag must not also open or tick the card.
        const swallow = (ce: MouseEvent) => {
          ce.stopPropagation();
          ce.preventDefault();
        };
        window.addEventListener("click", swallow, { capture: true, once: true });
        setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0);
        // Where you let go counts, even if the preview hadn't caught up yet
        // (a quick drag can be released before the 70ms settle delay).
        let target = overRef.current;
        const zone = zoneAt(last.y);
        if (zone) target = spotIn(zone.grid, zone.status, last.x, last.y, id) ?? target;
        commit(null);
        setDragging(null);
        if (drop && target && id !== target.beforeId) {
          setLanded(id);
          onDropRef.current(id, target);
        }
      };
      const up = (ev: globalThis.PointerEvent) => {
        last = { x: ev.clientX, y: ev.clientY };
        end(true);
      };
      const key = (ke: KeyboardEvent) => {
        if (ke.key === "Escape") end(false);
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up);
      window.addEventListener("keydown", key);
    },
  });

  /** CSS class for a section: tinted while it's the drop target. */
  const zoneClass = (status: Status) => (over?.status === status ? "zone over" : "zone");
  /** True while a card is being dragged over `status`. */
  const isOver = (status: Status) => !!dragging && over?.status === status;
  /** The drop preview for the list `status`, see `dropPreview`. */
  const preview = (status: Status, ids: string[]) =>
    dragging && isOver(status) && status !== "done" ? dropPreview(ids, dragging, over?.beforeId) : null;

  return { card, zoneClass, isOver, preview, dragging, landed };
}
