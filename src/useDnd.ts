// Native HTML5 drag and drop: drag any card onto Today, Backlog or Done,
// or onto another card to drop it in front of that card.
//
// While you drag, `over` says where the card would land. App renders a
// faded "ghost" copy of the card in that spot, and the section gets a soft
// background tint. The drop itself is handled once, by the section, using
// that same `over` value, so what you see is exactly what you get.

import { useRef, useState, type DragEvent } from "react";
import type { Status } from "./types";

export type DropTarget = { status: Status; beforeId?: string };

export function useDnd(onDrop: (id: string, target: DropTarget) => void) {
  const dragId = useRef<string | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOverState] = useState<DropTarget | null>(null);
  // The card you just dropped. It stays still (no hover lift) until the mouse
  // leaves it, so a drop ends calmly instead of with an extra bounce.
  const [landed, setLanded] = useState<string | null>(null);
  const overRef = useRef<DropTarget | null>(null);

  const setOver = (t: DropTarget | null) => {
    const cur = overRef.current;
    if (cur?.status === t?.status && cur?.beforeId === t?.beforeId) return;
    overRef.current = t;
    setOverState(t);
  };
  const readId = (e: DragEvent) => {
    let id = dragId.current;
    try { id = id || e.dataTransfer.getData("text/plain"); } catch { /* ignore */ }
    return id;
  };
  const finish = () => { dragId.current = null; overRef.current = null; setDragging(null); setOverState(null); };
  const allow = (e: DragEvent) => { e.preventDefault(); e.stopPropagation(); };

  /** Props for a draggable card. Hovering its left half means "before me",
   *  its right half "after me" (= before `nextId`, or at the end). Both sides of
   *  a gap therefore point at the same spot, so the preview doesn't flip back
   *  and forth as cards shift under the cursor. */
  const card = (id: string, status: Status, nextId?: string) => ({
    draggable: true,
    onDragStart: (e: DragEvent) => {
      dragId.current = id;
      try { e.dataTransfer.setData("text/plain", id); e.dataTransfer.effectAllowed = "move"; } catch { /* ignore */ }
      setTimeout(() => setDragging(id), 0); // after the browser takes its drag snapshot
    },
    onDragEnd: finish,
    onMouseLeave: () => setLanded((l) => (l === id ? null : l)),
    onDragOver: (e: DragEvent) => {
      allow(e);
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const after = e.clientX > r.left + r.width / 2;
      setOver({ status, beforeId: after ? nextId : id });
    },
  });

  /** The grid inside a section. Gaps between cards keep the current spot (no flicker);
   *  entering from outside means "at the end". */
  const grid = (status: Status) => ({
    onDragOver: (e: DragEvent) => { allow(e); if (overRef.current?.status !== status) setOver({ status }); },
  });

  /** The ghost itself: hovering it keeps everything as it is. */
  const ghost = { onDragOver: allow };

  /** Props for a whole section. */
  const zone = (status: Status) => ({
    className: over?.status === status ? "zone over" : "zone",
    onDragOver: (e: DragEvent) => { allow(e); setOver({ status }); },
    onDrop: (e: DragEvent) => {
      e.preventDefault();
      const dropped = readId(e);
      const target = overRef.current ?? { status };
      finish();
      if (dropped && dropped !== target.beforeId) { setLanded(dropped); onDrop(dropped, target); }
    },
  });

  /** Put on the page: dragging over anything that isn't a section clears the preview. */
  const outside = { onDragOver: () => setOver(null) };

  return { card, grid, ghost, zone, outside, dragging, over, landed };
}
