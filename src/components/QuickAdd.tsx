// The quick add box: type, pick a colour (click or ⌘1–6), Tab to choose
// Today or Backlog, Enter to add, Esc to close.

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type { Category, Status } from "../types";

interface Props {
  categories: Category[];
  colourOf: (id: string) => string;
  initialColour: string;
  onAdd: (title: string, colour: string, status: Status) => void;
  onClose: () => void;
}

const WHERE: { key: Status; name: string }[] = [{ key: "today", name: "Today" }, { key: "backlog", name: "Backlog" }];

export function QuickAdd({ categories, colourOf, initialColour, onAdd, onClose }: Props) {
  const [text, setText] = useState("");
  const [colour, setColour] = useState(initialColour);
  const [where, setWhere] = useState<Status>("today");
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => input.current?.focus(), []);

  const onKey = (e: KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      if (text.trim()) onAdd(text.trim(), colour, where);
    } else if (e.key === "Escape") {
      onClose();
    } else if (e.key === "Tab") {
      e.preventDefault();
      setWhere((w) => (w === "today" ? "backlog" : "today"));
    } else if ((e.metaKey || e.ctrlKey) && /^[1-6]$/.test(e.key)) {
      const c = categories[Number(e.key) - 1];
      if (c) { e.preventDefault(); setColour(c.id); }
    }
  };

  const ringed = (id: string) => ({
    width: 14, height: 14, background: colourOf(id),
    boxShadow: id === colour ? `0 0 0 3px var(--surface), 0 0 0 4.5px ${colourOf(id)}` : "none",
  });

  return (
    <div className="quick-wrap">
      <div className="scrim" onClick={onClose} />
      <div className="quick themed" role="dialog" aria-label="New task">
        <div className="quick-top">
          <span className="dot" style={{ width: 12, height: 12, flex: "none", background: colourOf(colour) }} />
          <label htmlFor="quick-input" className="sr-only">New task</label>
          <input id="quick-input" ref={input} className="quick-input" value={text} onChange={(e) => setText(e.target.value)} onKeyDown={onKey} placeholder="What needs doing?" />
        </div>
        <div className="quick-opts">
          <div style={{ display: "flex", alignItems: "center", gap: 2 }}>
            {categories.map((c, i) => (
              <button key={c.id} type="button" className="dotbtn" onClick={() => setColour(c.id)} aria-label={c.name} aria-pressed={c.id === colour} title={`${c.name}  ⌘${i + 1}`} style={{ width: 34, height: 34 }}>
                <span className="dot" style={ringed(c.id)} />
              </button>
            ))}
          </div>
          <div className="segmented themed">
            {WHERE.map((w) => (
              <button key={w.key} type="button" className={w.key === where ? "seg on" : "seg"} aria-pressed={w.key === where} onClick={() => setWhere(w.key)}>{w.name}</button>
            ))}
          </div>
        </div>
        <div className="quick-hint mono themed">⏎ add · ⌘1–{categories.length} category · tab where · esc</div>
      </div>
    </div>
  );
}
