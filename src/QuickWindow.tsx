// What the ⌥ Space window shows: only the quick-add box, floating over
// whatever you're doing. The window itself is see-through (set up in lib.rs),
// so the box's rounded corners and shadow sit directly on your desktop.
// The new task is written straight to the vault; the board window notices the
// new file through its folder watcher and shows it.

import { useCallback, useEffect, useState } from "react";
import { api } from "./api";
import { colours, themeVars } from "./themes";
import { nowStamp } from "./useBoard";
import { QuickAdd } from "./components/QuickAdd";
import type { Settings, Status, ThemeKey } from "./types";

export function QuickWindow() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [open, setOpen] = useState(false);
  const [session, setSession] = useState(0); // a fresh box (empty, animated) on every open
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => {
    // Empty the window first, then hide it, so the next open never flashes the old box.
    setOpen(false);
    requestAnimationFrame(() => requestAnimationFrame(() => api.hideQuick()));
  }, []);

  useEffect(() => {
    api.getSettings().then(setSettings);
    let unlisten: (() => void) | undefined;
    api.onQuickOpen(() => {
      api.getSettings().then(setSettings); // categories may have changed in the board window
      setError(null);
      setSession((n) => n + 1);
      setOpen(true);
    }).then((u) => (unlisten = u));
    // Clicking anywhere outside the box (another app, the desktop) closes it.
    window.addEventListener("blur", close);
    return () => { unlisten?.(); window.removeEventListener("blur", close); };
  }, [close]);

  const add = async (title: string, area: string, status: Status) => {
    try {
      // New tasks go on top: 1024 above the smallest order in that list.
      const orders = (await api.listTasks()).filter((t) => t.status === status).map((t) => t.order);
      const order = orders.length ? Math.min(...orders) - 1024 : 0;
      await api.saveTask({ id: "", title, area, status, order, focus: false, created: nowStamp(), doneOn: null, items: [], notes: "" });
      close();
    } catch (e) {
      setError(String(e));
    }
  };

  if (!settings || !open) return null;
  const theme = settings.theme as ThemeKey;
  const cats = settings.categories;
  const colourOf = (id: string) => colours(theme, cats.find((c) => c.id === id)?.color ?? "slate").strong;

  return (
    <div className="quick-window" style={themeVars(theme)}>
      <QuickAdd key={session} floating categories={cats} colourOf={colourOf} initialColour={cats[0]?.id ?? ""} onAdd={add} onClose={close} />
      {error && <div className="quick-error">{error}</div>}
    </div>
  );
}
