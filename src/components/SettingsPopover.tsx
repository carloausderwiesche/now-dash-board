import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import { THEMES, PALETTE_KEYS } from "../themes";
import type { Board } from "../useBoard";
import type { PaletteKey, Settings, ThemeKey } from "../types";
import { CloseIcon, DownIcon } from "./Icons";

const GROUPS = ["Rams", "Ive", "Pastel"] as const;
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
  const vaultOptions = settings.vaultPath && !vaults.includes(settings.vaultPath) ? [settings.vaultPath, ...vaults] : vaults;
  const setCat = (id: string, p: Partial<(typeof cats)[number]>) =>
    board.updateSettings({ categories: cats.map((x) => (x.id === id ? { ...x, ...p } : x)) });

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

        <div className="field-group" ref={catList}>
          <span className="cap">Categories</span>
          {cats.map((c) => (
            <div key={c.id} className="cat-block">
              <div className="cat-row">
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
                        <span className="dot" style={{ width: 16, height: 16, background: col, boxShadow: on ? `0 0 0 3px var(--surface), 0 0 0 4.5px ${col}` : "none" }} />
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
          <span style={{ fontSize: 12, color: "var(--muted)" }}>Tasks live in <span className="mono">{settings.tasksFolder}/</span>, finished ones are logged in <span className="mono">{settings.dailyFolder}/</span>.</span>
        </div>
      </div>
    </>
  );
}
