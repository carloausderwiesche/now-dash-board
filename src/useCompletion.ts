// The "done" animation: ring fills → title strikes → card flies into Done →
// counter bumps. Also queues cards finished outside the app (Obsidian, an
// agent), so they get the same animation, one at a time.

import { useCallback, useRef, useState } from "react";
import type { Task } from "./types";

/** Ring + fly: `.card.completing` in styles.css (.42s delay + .46s fly). */
export const COMPLETE_MS = 880;
/** How long the Done number keeps its `.bump` class (the animation is .5s). */
const BUMP_MS = 650;

export function useCompletion() {
  const [completing, setCompleting] = useState<string | null>(null);
  const [bump, setBump] = useState(false);
  const [lastDone, setLastDone] = useState<string | null>(null);
  const [incoming, setIncoming] = useState<string[]>([]);
  /** The file's version of each card in `incoming`. */
  const fromDisk = useRef(new Map<string, Task>());

  const queue = useCallback((finished: Task[]) => {
    if (!finished.length) return;
    finished.forEach((t) => fromDisk.current.set(t.id, t));
    const ids = finished.map((t) => t.id);
    setIncoming((q) => [...q.filter((id) => !ids.includes(id)), ...ids]);
  }, []);

  const forget = useCallback((id: string) => {
    fromDisk.current.delete(id);
    setIncoming((q) => q.filter((x) => x !== id));
  }, []);

  /** Plays the animation for `id`, then calls `land` with the file's version if
   *  it was finished on disk. `land` returns the title for "Last: …", or null
   *  when the card is gone (no bump then). */
  const play = useCallback((id: string, land: (onDisk?: Task) => string | null) => {
    setCompleting(id);
    setIncoming((q) => q.filter((x) => x !== id));
    window.setTimeout(() => {
      setCompleting(null);
      const onDisk = fromDisk.current.get(id);
      fromDisk.current.delete(id);
      const title = land(onDisk);
      if (title === null) return;
      setLastDone(title);
      setBump(true);
      window.setTimeout(() => setBump(false), BUMP_MS);
    }, COMPLETE_MS);
  }, []);

  return { completing, bump, lastDone, incoming, queue, forget, play };
}
