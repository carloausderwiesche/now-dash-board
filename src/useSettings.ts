// Settings state, saved to disk 400 ms after the last change.

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "./api";
import { PALETTE_KEYS, THEMES } from "./themes";
import type { Category, Settings } from "./types";

const SAVE_DELAY_MS = 400;

/** `reload` runs after a save that changes where the tasks are (e.g. a new vault). */
export function useSettings(reload: () => void) {
  const [settings, setSettings] = useState<Settings | null>(null);
  const timer = useRef<number>();

  useEffect(() => {
    // A theme that no longer exists (e.g. the removed "mint") falls back to Braun.
    api.getSettings().then((s) => setSettings(s.theme in THEMES ? s : { ...s, theme: "braun" }));
  }, []);

  const updateSettings = useCallback(
    (p: Partial<Settings>, opts: { reloadAfter?: boolean } = {}) => {
      setSettings((s) => {
        if (!s) return s;
        const next = { ...s, ...p };
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(async () => {
          await api.saveSettings(next);
          if (opts.reloadAfter) reload();
        }, SAVE_DELAY_MS);
        return next;
      });
    },
    [reload],
  );

  const addCategory = useCallback(() => {
    if (!settings) return;
    const used = settings.categories.map((c) => c.color);
    const color = PALETTE_KEYS.find((k) => !used.includes(k)) ?? "slate";
    let id = "category",
      n = 2;
    while (settings.categories.some((c) => c.id === id)) id = `category-${n++}`;
    const cat: Category = { id, name: "New category", color };
    updateSettings({ categories: [...settings.categories, cat] });
  }, [settings, updateSettings]);

  /** Removes a category from settings. Task files keep their `area:` value;
   *  until you pick a new category they show in the first one. */
  const removeCategory = useCallback(
    (id: string) => {
      if (!settings || settings.categories.length <= 1) return;
      updateSettings({ categories: settings.categories.filter((c) => c.id !== id) });
    },
    [settings, updateSettings],
  );

  return { settings, updateSettings, addCategory, removeCategory };
}
