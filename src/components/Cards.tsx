import type { CSSProperties, MouseEvent, PointerEvent } from "react";
import type { Task } from "../types";
import { FocusIcon, LockIcon, PauseIcon, Tick } from "./Icons";

type DndProps = {
  onPointerDown: (e: PointerEvent) => void;
  onMouseLeave: () => void;
};

/** Where a completing card flies to (the Done number), relative to the card's centre. */
export type Flight = { x: number; y: number };

interface CardProps {
  task: Task;
  strong: string;
  tint: string;
  /** Name of the card's category, shown when hovering its dot. */
  catName: string;
  flags: { dim: boolean; dragging: boolean; collapsed: boolean; completing: boolean; arrived: boolean; landed: boolean; open: boolean };
  dnd: DndProps;
  flight?: Flight | null;
  onOpen: () => void;
  onCycleColour: () => void;
  onContextMenu?: (e: MouseEvent) => void;
}

function classes(base: string, f: CardProps["flags"], extra = "") {
  return [
    base,
    extra,
    f.dim && "dim",
    f.dragging && "dragging",
    f.collapsed && "collapsed",
    f.completing && "completing",
    f.arrived && "arrive",
    f.landed && "landed",
    f.open && "open",
  ]
    .filter(Boolean)
    .join(" ");
}

/** Marks the title as cut off ("…") when it is, so the full-title tooltip only
 *  shows up when there's something hidden. Measured on hover, so it's always current. */
const markClipped = (e: { currentTarget: HTMLElement }) => {
  const clamp = e.currentTarget.querySelector(".clamp");
  if (clamp) e.currentTarget.toggleAttribute("data-clipped", clamp.scrollHeight > clamp.clientHeight + 1);
};

const flightVars = (f?: Flight | null) => (f ? ({ "--fx": `${f.x}px`, "--fy": `${f.y}px` } as CSSProperties) : {});

const dot = (color: string, size: number, ring?: string): CSSProperties => ({
  width: size,
  height: size,
  background: color,
  outline: ring ? `2px solid ${ring}` : undefined,
});

/** A big tinted card in Today. Optional "focus" turns it black and double width. */
export function TodayCard(p: CardProps & { onComplete: () => void; onToggleFocus: () => void }) {
  const { task } = p;
  const done = task.items.filter((x) => x.done).length;
  return (
    <div
      className={classes("card today-card themed", p.flags, task.focus ? "is-focus" : "")}
      style={{ backgroundColor: p.tint, ...flightVars(p.flight) }}
      data-flip={task.id}
      onContextMenu={p.onContextMenu}
      {...p.dnd}
    >
      <button
        type="button"
        className="opener title"
        onClick={p.onOpen}
        data-full={task.title}
        onMouseEnter={markClipped}
        onFocus={markClipped}
      >
        <span className="clamp">
          <span className="ttl">{task.title}</span>
          {task.private && (
            <span className="lock" data-tip="Private: AI won't use it">
              <LockIcon />
            </span>
          )}
        </span>
        {task.items.length > 0 && (
          <span className="sub mono num">
            {done} / {task.items.length}
          </span>
        )}
      </button>
      <div className="card-foot">
        <button
          type="button"
          className="dotbtn"
          onClick={p.onCycleColour}
          aria-label={`${p.catName}, click to change category`}
          data-tip={p.catName}
          style={{ width: 32, height: 32, marginLeft: -8 }}
        >
          <span className="dot" style={dot(p.strong, 10, task.focus ? "var(--ink)" : undefined)} />
        </button>
        {task.focus && (
          <span className="cap" style={{ opacity: 0.8 }}>
            Now
          </span>
        )}
        <span className="spacer" />
        <button
          type="button"
          className="iconbtn reveal small-btn"
          onClick={p.onToggleFocus}
          title={task.focus ? "Stop focusing on this" : "Focus on this now"}
        >
          {task.focus ? (
            <>
              Pause <PauseIcon />
            </>
          ) : (
            <>
              Focus <FocusIcon />
            </>
          )}
        </button>
        <button type="button" className="ringbtn" onClick={p.onComplete} aria-label="Mark done">
          <span className="ring">
            <Tick />
          </span>
        </button>
      </div>
    </div>
  );
}

/** A small plain card in the Backlog. */
export function BacklogCard(p: CardProps & { onToToday: () => void }) {
  return (
    <div
      className={classes("card backlog-card themed", p.flags)}
      style={flightVars(p.flight)}
      data-flip={p.task.id}
      onContextMenu={p.onContextMenu}
      {...p.dnd}
    >
      <button
        type="button"
        className="opener title"
        onClick={p.onOpen}
        data-full={p.task.title}
        onMouseEnter={markClipped}
        onFocus={markClipped}
      >
        <span className="clamp">
          <span className="ttl">{p.task.title}</span>
          {p.task.private && (
            <span className="lock" data-tip="Private: AI won't use it">
              <LockIcon size={11} />
            </span>
          )}
        </span>
      </button>
      <div className="card-foot">
        <button
          type="button"
          className="dotbtn"
          onClick={p.onCycleColour}
          aria-label={`${p.catName}, click to change category`}
          data-tip={p.catName}
          style={{ width: 28, height: 28, marginLeft: -7 }}
        >
          <span className="dot" style={dot(p.strong, 10)} />
        </button>
        <span className="spacer" />
        <button
          type="button"
          className="iconbtn reveal"
          onClick={p.onToToday}
          style={{ height: 28, padding: "0 6px", fontSize: 12, fontWeight: 500, color: "var(--ink)" }}
        >
          Today ↑
        </button>
      </div>
    </div>
  );
}

/** The faded preview of the card you're dragging, shown where it will land. */
export function GhostCard({
  id,
  kind,
  title,
  tint,
  focus,
}: {
  id: string;
  kind: "today" | "backlog";
  title: string;
  tint: string;
  focus: boolean;
}) {
  // A focus card keeps its look (double width, ink) in Today; moving it to Backlog ends focus.
  const isFocus = focus && kind === "today";
  return (
    <div
      className={`card ${kind}-card ghost${isFocus ? " is-focus" : ""}`}
      style={kind === "today" ? { backgroundColor: tint } : undefined}
      data-flip="__ghost__"
      data-ghost-for={id}
      aria-hidden
    >
      <span className="title">
        <span className="ttl">{title}</span>
      </span>
    </div>
  );
}
