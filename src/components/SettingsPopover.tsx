import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import { THEMES, PALETTE_KEYS } from "../themes";
import type { Board } from "../useBoard";
import type { Category, PaletteKey, Settings, ThemeKey } from "../types";
import { CloseIcon, DownIcon, GripIcon } from "./Icons";
import { ring } from "./ring";

const GROUPS = ["Rams", "Ive", "Pastel", "Eames"] as const;
const CHOOSE = "__choose__";
const baseName = (p: string) => p.replace(/[/\\]+$/, "").split(/[/\\]/).pop() || p;

interface Props {
  settings: Settings;
  board: Board;
  /** Category id → its strong colour. */
  colourOf: (id: string) => string;
  /** Palette key → its strong colour in the current theme. */
  paletteColour: (key: PaletteKey) => string;
  onClose: () => void;
}

export function SettingsPopover({ settings, board, colourOf, paletteColour, onClose }: Props) {
  const cats = settings.categories;
  const [picking, setPicking] = useState<string | null>(null); // category whose colour picker is open
  const [vaults, setVaults] = useState<string[]>([]);

  useEffect(() => { api.knownVaults().then(setVaults).catch(() => setVaults([])); }, []);

  // The colour palette floats over the settings; a click anywhere outside it closes it.
  const pickerRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!picking) return;
    const onDown = (e: MouseEvent) => {
      const t = e.target as HTMLElement;
      if (!pickerRef.current?.contains(t) && !t.closest("[data-picker-toggle]")) setPicking(null);
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [picking]);

  // A new category arrives as "New category": put the cursor in its name, text selected, so you just type.
  const catList = useRef<HTMLDivElement>(null);
  const count = useRef(cats.length);
  useEffect(() => {
    if (cats.length > count.current) {
      const inputs = catList.current?.querySelectorAll<HTMLInputElement>(".cat-row input");
      inputs?.[inputs.length - 1]?.select();
    }
    count.current = cats.length;
  }, [cats.length]);

  const setVault = (path: string) => board.updateSettings({ vaultPath: path }, { reloadAfter: true });
  const chooseFolder = async () => {
    const path = await api.pickFolder();
    if (path) setVault(path);
  };
  // Where finished tasks are logged: a folder inside the vault, stored relative to it.
  const [dailyError, setDailyError] = useState<string | null>(null);
  const chooseDailyFolder = async () => {
    const vault = settings.vaultPath.replace(/[/\\]+$/, "");
    const path = await api.pickFolder({ title: "Where should finished tasks be logged?", start: `${vault}/${settings.dailyFolder}` });
    if (!path) return;
    const inside = path === vault || path.startsWith(vault + "/") || path.startsWith(vault + "\\");
    if (!inside) { setDailyError("Choose a folder inside your vault."); return; }
    setDailyError(null);
    board.updateSettings({ dailyFolder: path.slice(vault.length).replace(/^[/\\]+/, "") });
  };
  const vaultOptions = settings.vaultPath && !vaults.includes(settings.vaultPath) ? [settings.vaultPath, ...vaults] : vaults;
  const setCat = (id: string, p: Partial<(typeof cats)[number]>) =>
    board.updateSettings({ categories: cats.map((x) => (x.id === id ? { ...x, ...p } : x)) });

  // ---- reordering: drag a row by its grip (or focus the grip and use ↑ ↓) ----
  // The order matters: it's the order of the dots in the header, in quick add (⌘1…) and when cycling.
  const moved = (list: Category[], from: number, to: number) => {
    const next = [...list];
    next.splice(to, 0, ...next.splice(from, 1));
    return next;
  };
  // Rows never change places in the page while you drag (moving the dragged
  // element would make the browser drop the pointer, which is what made dragging
  // stick). Instead every row gets a vertical offset, and the real reorder
  // happens once, after you let go.
  type Drag = { id: string; from: number; to: number; dy: number; rowH: number; startY: number; dropping: boolean };
  const [drag, setDrag] = useState<Drag | null>(null);
  const [settling, setSettling] = useState(false); // the frame right after the reorder: no slide animation
  const dragRef = useRef<Drag | null>(null);
  dragRef.current = drag;

  const startDrag = (e: React.PointerEvent<HTMLButtonElement>, id: string) => {
    if (e.button !== 0 || dragRef.current) return;
    e.preventDefault(); // no text selection while dragging
    const block = e.currentTarget.closest(".cat-block") as HTMLElement;
    const gap = parseFloat(getComputedStyle(block.parentElement!).rowGap) || 0;
    setPicking(null);
    const from = cats.findIndex((c) => c.id === id);
    setDrag({ id, from, to: from, dy: 0, rowH: block.offsetHeight + gap, startY: e.clientY, dropping: false });
  };

  // While dragging, listen on the whole window, so it works wherever the pointer goes.
  const dragging = !!drag && !drag.dropping;
  useEffect(() => {
    if (!dragging) return;
    const finish = () => {
      const d = dragRef.current;
      if (!d) return;
      if (d.to === d.from) { setDrag(null); return; }
      // Glide into the slot first, then reorder for real (with animations off for that one frame).
      setDrag({ ...d, dy: (d.to - d.from) * d.rowH, dropping: true });
      setTimeout(() => {
        setSettling(true);
        board.updateSettings({ categories: moved(cats, d.from, d.to) });
        setDrag(null);
        requestAnimationFrame(() => requestAnimationFrame(() => setSettling(false)));
      }, 160);
    };
    const onMove = (e: PointerEvent) => {
      const d = dragRef.current;
      if (!d) return;
      if (e.buttons === 0) { finish(); return; } // the button came up somewhere we didn't hear about
      // Keep the row inside the list: from the first slot to the last, never past them.
      const dy = Math.max(-d.from * d.rowH, Math.min((cats.length - 1 - d.from) * d.rowH, e.clientY - d.startY));
      setDrag({ ...d, dy, to: d.from + Math.round(dy / d.rowH) });
    };
    const cancel = () => setDrag(null);
    // Esc cancels the drag only: caught on the document (before the window, where
    // Esc would close the whole popover) and stopped there.
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); cancel(); } };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", finish);
    window.addEventListener("pointercancel", cancel);
    window.addEventListener("blur", cancel); // e.g. switching apps mid-drag
    document.addEventListener("keydown", onKey, true);
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", finish);
      window.removeEventListener("pointercancel", cancel);
      window.removeEventListener("blur", cancel);
      document.removeEventListener("keydown", onKey, true);
    };
  }, [dragging, cats, board]);

  /** How far a row is pushed while dragging: the dragged one follows the pointer,
   *  the ones it has passed slide one row the other way. */
  const offsetOf = (i: number, id: string) => {
    if (!drag) return 0;
    if (id === drag.id) return drag.dy;
    if (drag.from < i && i <= drag.to) return -drag.rowH;
    if (drag.to <= i && i < drag.from) return drag.rowH;
    return 0;
  };
  const nudge = (id: string, by: number) => {
    const from = cats.findIndex((c) => c.id === id);
    const to = from + by;
    if (to >= 0 && to < cats.length) board.updateSettings({ categories: moved(cats, from, to) });
  };

  return (
    <>
      {/* Invisible layer behind the popover: clicking anywhere outside closes it. */}
      <div className="popover-catch" onMouseDown={onClose} />
      <div className="popover themed" role="dialog" aria-label="Settings">
        <div className="field-group">
          <label htmlFor="theme" className="cap">Theme</label>
          <div className="select-wrap">
            <select id="theme" className="sel themed" value={settings.theme} onChange={(e) => board.updateSettings({ theme: e.target.value as ThemeKey })}>
              {GROUPS.map((g) => (
                <optgroup key={g} label={g}>
                  {(Object.keys(THEMES) as ThemeKey[]).filter((k) => THEMES[k].group === g).map((k) => (
                    <option key={k} value={k}>{THEMES[k].name}</option>
                  ))}
                </optgroup>
              ))}
            </select>
            <DownIcon />
          </div>
        </div>

        <div className="field-group">
          <span className="cap">Cards</span>
          <div className="segmented themed" role="group" aria-label="Card size" style={{ alignSelf: "flex-start" }}>
            {([false, true] as const).map((c) => (
              <button key={String(c)} type="button" className={!!settings.compact === c ? "seg on" : "seg"} aria-pressed={!!settings.compact === c}
                onClick={() => board.updateSettings({ compact: c })}>
                {c ? "Compact" : "Roomy"}
              </button>
            ))}
          </div>
        </div>

        <div className="field-group" ref={catList}>
          <span className="cap">Categories</span>
          {cats.map((c, i) => (
            <div key={c.id}
              className={["cat-block", drag?.id === c.id && "lifted", drag?.id === c.id && !drag.dropping && "following", drag && "sorting", settling && "settling"].filter(Boolean).join(" ")}
              style={drag ? { transform: `translateY(${offsetOf(i, c.id)}px)` } : undefined}>
              <div className="cat-row">
                {cats.length > 1 && (
                  <button type="button" className="iconbtn cat-grip" aria-label={`Reorder ${c.name}`} title="Drag to reorder"
                    onPointerDown={(e) => startDrag(e, c.id)}
                    onKeyDown={(e) => {
                      if (e.key === "ArrowUp" || e.key === "ArrowDown") { e.preventDefault(); nudge(c.id, e.key === "ArrowUp" ? -1 : 1); }
                    }}>
                    <GripIcon />
                  </button>
                )}
                <button type="button" className="dotbtn" style={{ width: 36, height: 36 }} aria-label={`Choose colour for ${c.name}`}
                  aria-expanded={picking === c.id} data-picker-toggle onClick={() => setPicking(picking === c.id ? null : c.id)}>
                  <span className="dot" style={{ width: 14, height: 14, background: colourOf(c.id) }} />
                </button>
                <input aria-label="Category name" value={c.name} onChange={(e) => setCat(c.id, { name: e.target.value })} />
                {cats.length > 1 && (
                  <button type="button" className="iconbtn cat-del" onClick={() => { board.removeCategory(c.id); setPicking(null); }}
                    aria-label={`Delete ${c.name}`} title={`Delete ${c.name}`}>
                    <CloseIcon />
                  </button>
                )}
              </div>
              {picking === c.id && (
                <div className="swatches" ref={pickerRef} role="radiogroup" aria-label={`Colour for ${c.name}`}>
                  {PALETTE_KEYS.map((k) => {
                    const on = c.color === k;
                    const col = paletteColour(k);
                    return (
                      <button key={k} type="button" role="radio" aria-checked={on} aria-label={k} className="dotbtn"
                        style={{ width: 30, height: 30 }} onClick={() => { setCat(c.id, { color: k }); setPicking(null); }}>
                        <span className="dot" style={{ width: 16, height: 16, background: col, ...ring(on, col) }} />
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          ))}
          {cats.length < 6 && (
            <button type="button" className="iconbtn" onClick={board.addCategory} style={{ height: 36, textAlign: "left", padding: "0 8px", fontSize: 13 }}>+ Category</button>
          )}
        </div>

        <div className="field-group">
          <label htmlFor="vault" className="cap">Obsidian vault</label>
          <div className="vault-row">
            {vaultOptions.length > 0 ? (
              <div className="select-wrap" style={{ flex: 1, minWidth: 0 }}>
                <select id="vault" className="sel themed" value={settings.vaultPath || ""} title={settings.vaultPath}
                  onChange={(e) => (e.target.value === CHOOSE ? chooseFolder() : setVault(e.target.value))}>
                  {!settings.vaultPath && <option value="" disabled>Choose a vault</option>}
                  {vaultOptions.map((p) => <option key={p} value={p}>{baseName(p)}</option>)}
                  <option value={CHOOSE}>Other folder…</option>
                </select>
                <DownIcon />
              </div>
            ) : (
              <>
                <span id="vault" className="vault-path mono" title={settings.vaultPath}>{settings.vaultPath || "No vault chosen"}</span>
                <button type="button" className="btn-small themed" onClick={chooseFolder}>Choose…</button>
              </>
            )}
          </div>
          {settings.vaultPath && vaultOptions.length > 0 && <span className="vault-path mono" title={settings.vaultPath}>{settings.vaultPath}</span>}
          <span style={{ fontSize: 12, color: "var(--muted)" }}>Tasks live in <span className="mono">{settings.tasksFolder}/</span>.</span>
        </div>

        <div className="field-group">
          <span className="cap">Finished tasks are logged in</span>
          <div className="vault-row">
            <span className="vault-path mono" title="One daily note per day, e.g. 2026-11-22.md">{settings.dailyFolder ? `${settings.dailyFolder}/` : "the vault's top folder"}</span>
            <button type="button" className="btn-small themed" onClick={chooseDailyFolder} disabled={!settings.vaultPath}>Choose…</button>
          </div>
          {dailyError && <span style={{ fontSize: 12, color: "var(--accent)" }}>{dailyError}</span>}
        </div>
      </div>
    </>
  );
}
