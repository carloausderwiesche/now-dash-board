import type { ReactNode } from "react";
import type { Category } from "../types";
import { PlusIcon, SlidersIcon } from "./Icons";
import { ring } from "./ring";

/** Today's date, the category filter dots, settings and the + button. */
export function Header(p: {
  categories: Category[];
  /** The highlighted category, or null for all. */
  filter: string | null;
  onFilter: (id: string | null) => void;
  colourOf: (area: string) => string;
  settingsOpen: boolean;
  onToggleSettings: () => void;
  onAdd: () => void;
  /** The settings popover, shown under the tools while open. */
  children?: ReactNode;
}) {
  const now = new Date();
  return (
    <header className="header" data-tauri-drag-region>
      <div className="date">
        <span className="date-day num">{now.getDate()}</span>
        <div className="date-text">
          <span className="weekday">{now.toLocaleDateString("en-GB", { weekday: "long" })}</span>
          <span className="month">{now.toLocaleDateString("en-GB", { month: "long" })}</span>
        </div>
      </div>
      <div className="tools">
        {p.categories.map((c) => {
          const on = p.filter === c.id;
          const col = p.colourOf(c.id);
          return (
            <button
              key={c.id}
              type="button"
              className="dotbtn filter-btn"
              onClick={() => p.onFilter(on ? null : c.id)}
              aria-label={`Highlight ${c.name}`}
              aria-pressed={on}
              data-tip={c.name}
            >
              <span
                className="dot"
                style={{ width: 12, height: 12, background: col, opacity: p.filter && !on ? 0.35 : 1, ...ring(on, col) }}
              />
            </button>
          );
        })}
        <span className="divider themed" />
        <button
          type="button"
          className="iconbtn settings-btn"
          onClick={p.onToggleSettings}
          aria-label="Settings"
          aria-expanded={p.settingsOpen}
        >
          <SlidersIcon />
        </button>
        <button type="button" className="plus" onClick={p.onAdd} aria-label="Add task" title="Add task  ⌥ Space">
          <PlusIcon />
        </button>
        {p.children}
      </div>
    </header>
  );
}
