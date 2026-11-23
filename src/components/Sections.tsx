import { useState, type ReactNode, type Ref } from "react";
import { todayStr } from "../board";
import type { Task } from "../types";
import { ChevronIcon } from "./Icons";

/** Today or Backlog: heading with a count, the card grid, and an empty state. */
export function CardSection(p: {
  status: "today" | "backlog";
  label: string;
  zoneClass: string;
  gridRef: Ref<HTMLDivElement>;
  cards: ReactNode[];
  /** The drag preview and where it goes among the cards. */
  ghost: { index: number; node: ReactNode } | null;
  /** Shown in the heading, e.g. while a category is highlighted that this list doesn't have. */
  note: string | null;
  empty: { title: string; hint: string } | null;
}) {
  const shown = p.ghost ? [...p.cards.slice(0, p.ghost.index), p.ghost.node, ...p.cards.slice(p.ghost.index)] : p.cards;
  return (
    <section aria-label={p.label} data-section={p.status} className={"section " + p.zoneClass}>
      <div className="section-head themed">
        <h2>{p.label}</h2>
        <span className="count num">{p.cards.length}</span>
        {p.note && <span className="head-note">{p.note}</span>}
      </div>
      <div className={`grid-${p.status}`} ref={p.gridRef} data-grid>
        {shown}
        {p.empty && (
          <div className={p.status === "today" ? "empty themed" : "empty small themed"}>
            <strong>{p.empty.title}</strong>
            <span>{p.empty.hint}</span>
          </div>
        )}
      </div>
    </section>
  );
}

/** Tasks an agent suggested: accept → Backlog, dismiss → file deleted. */
export function SuggestedSection(p: {
  tasks: Task[];
  colourOf: (area: string) => string;
  onOpen: (id: string) => void;
  onAccept: (id: string) => void;
  onDismiss: (id: string) => void;
}) {
  if (!p.tasks.length) return null;
  return (
    <section aria-label="Suggested" className="suggested">
      <span className="cap">Suggested</span>
      {p.tasks.map((t) => (
        <div key={t.id} className="suggest-row themed">
          <span className="dot" style={{ width: 8, height: 8, background: p.colourOf(t.area), flex: "none" }} />
          <button type="button" className="opener title" onClick={() => p.onOpen(t.id)}>
            {t.title}
          </button>
          {t.from && (
            <span className="from mono" title={t.from}>
              {t.from
                .replace(/^\[\[|\]\]$/g, "")
                .split("/")
                .pop()}
            </span>
          )}
          <button type="button" className="iconbtn small-btn ink-btn" onClick={() => p.onAccept(t.id)}>
            Accept
          </button>
          <button type="button" className="iconbtn small-btn" onClick={() => p.onDismiss(t.id)} title="Dismiss (deletes the file)">
            Dismiss
          </button>
        </div>
      ))}
    </section>
  );
}

const dayLabel = (stamp: string) => new Date(stamp.slice(0, 10) + "T12:00").toLocaleDateString("en-GB", { weekday: "short" });

/** The Done counter for today; opens to the last 7 days, newest first. */
export function DoneSection(p: {
  zoneClass: string;
  /** Finished in the last 7 days, newest first. */
  week: Task[];
  todayCount: number;
  lastDone: string | null;
  bump: boolean;
  /** The number completing cards fly to. */
  numRef: Ref<HTMLSpanElement>;
  colourOf: (area: string) => string;
  onUndo: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <section aria-label="Done" data-section="done" className={"done-zone " + p.zoneClass}>
      <button type="button" className="done-head themed" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        <span ref={p.numRef} className={p.bump ? "done-num num bump" : "done-num num"}>
          {p.todayCount}
        </span>
        <span className="done-label">
          <strong>Done today</strong>
          <span className="last">{p.lastDone ? `Last: ${p.lastDone}` : "Nothing finished yet today"}</span>
        </span>
        <span className="done-chevron">
          <ChevronIcon open={open} />
        </span>
      </button>
      {open && p.week.length === 0 && (
        <div className="done-row themed">
          <span className="done-empty">Nothing finished in the last 7 days</span>
        </div>
      )}
      {open &&
        p.week.map((t) => (
          <div key={t.id} className="done-row themed">
            <span className="done-dot">
              <span className="dot" style={{ width: 10, height: 10, background: p.colourOf(t.area) }} />
            </span>
            <span className="title">{t.title}</span>
            {t.doneOn && !t.doneOn.startsWith(todayStr()) && <span className="done-day">{dayLabel(t.doneOn)}</span>}
            <button type="button" className="iconbtn reveal small-btn ink-btn" onClick={() => p.onUndo(t.id)}>
              Undo
            </button>
          </div>
        ))}
    </section>
  );
}
