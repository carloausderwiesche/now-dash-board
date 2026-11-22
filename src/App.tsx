import { useEffect, useRef, useState, type ReactNode } from "react";
import { api, inTauri } from "./api";
import { colours, themeVars } from "./themes";
import { byOrder, todayStr, useBoard } from "./useBoard";
import { useDnd } from "./useDnd";
import { useFlip } from "./useFlip";
import { BacklogCard, GhostCard, TodayCard, type Flight } from "./components/Cards";
import { DetailPanel } from "./components/DetailPanel";
import { ChevronIcon, PlusIcon, SlidersIcon } from "./components/Icons";
import { QuickAdd } from "./components/QuickAdd";
import { SettingsPopover } from "./components/SettingsPopover";
import type { Status, Task, ThemeKey } from "./types";

export default function App() {
  const board = useBoard();
  const { tasks, settings } = board;
  const [filter, setFilter] = useState<string | null>(null);
  const [quick, setQuick] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [doneOpen, setDoneOpen] = useState(false);
  const [flight, setFlight] = useState<(Flight & { id: string }) | null>(null);
  const doneNum = useRef<HTMLSpanElement>(null);
  const todayGrid = useFlip<HTMLDivElement>();
  const backlogGrid = useFlip<HTMLDivElement>();

  /** Completes a task. First measures the path from the card to the Done
   *  number, so the card can fly exactly there (see .completing in styles.css). */
  const finish = (id: string) => {
    if (board.completing) return;
    const card = document.querySelector<HTMLElement>(`[data-flip="${CSS.escape(id)}"]`);
    const target = doneNum.current;
    if (card && target) {
      const a = card.getBoundingClientRect(), b = target.getBoundingClientRect();
      // If Done is below the fold, aim for the bottom edge of the window instead.
      const tx = b.left + b.width / 2, ty = Math.min(b.top + b.height / 2, window.innerHeight - 24);
      setFlight({ id, x: tx - (a.left + a.width / 2), y: ty - (a.top + a.height / 2) });
    }
    board.complete(id);
  };

  const dnd = useDnd((id, target) => {
    if (target.status === "done") finish(id);
    else board.move(id, target.status, target.beforeId, { quiet: true });
  });

  // ⌥ Space (global, from Rust) and N (inside the app) open quick add; Esc closes things.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    api.onQuickAdd(() => setQuick(true)).then((u) => (unlisten = u));
    const onKey = (e: KeyboardEvent) => {
      const typing = e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLSelectElement;
      if (e.key === "Escape") { setOpenId(null); setShowSettings(false); setQuick(false); }
      else if (!typing && (e.key === "n" || (e.altKey && e.code === "Space"))) { e.preventDefault(); setQuick(true); }
    };
    window.addEventListener("keydown", onKey);
    return () => { unlisten?.(); window.removeEventListener("keydown", onKey); };
  }, []);

  // No vault configured yet → open settings so the first step is obvious.
  useEffect(() => { if (board.error && settings && !settings.vaultPath) setShowSettings(true); }, [board.error, settings]);

  if (!settings) return null;
  const theme = settings.theme as ThemeKey;
  const cats = settings.categories;
  const catOf = (id: string) => cats.find((c) => c.id === id) ?? cats[0];
  const colourOf = (id: string) => colours(theme, catOf(id)?.color ?? "slate");

  const today = tasks.filter((t) => t.status === "today").sort(byOrder);
  const backlog = tasks.filter((t) => t.status === "backlog").sort(byOrder);
  const suggested = tasks.filter((t) => t.status === "suggested").sort(byOrder);
  // The big number counts today; the list shows the last 7 days, newest first.
  // Older done tasks stay on disk as history.
  const weekAgo = new Date(Date.now() - 6 * 864e5).toLocaleDateString("sv-SE");
  const doneWeek = tasks
    .filter((t) => t.status === "done" && t.doneOn && t.doneOn.slice(0, 10) >= weekAgo)
    .sort((a, b) => (b.doneOn ?? "").localeCompare(a.doneOn ?? "") || byOrder(a, b));
  const doneToday = doneWeek.filter((t) => t.doneOn!.startsWith(todayStr()));
  const lastDone = board.lastDone ?? doneToday[0]?.title ?? "—";
  const dayLabel = (stamp: string) => new Date(stamp.slice(0, 10) + "T12:00").toLocaleDateString("en-GB", { weekday: "short" });
  const openTask = tasks.find((t) => t.id === openId);

  // Where the drop preview goes. While dragging inside one list, the card's own
  // slot *is* the preview (it just fades), so nothing moves until you actually
  // point somewhere else. Then that slot closes and the preview opens there:
  // only the cards in between shift, by one place.
  const dragged = tasks.find((t) => t.id === dnd.dragging);
  const listOf = (s: Status) => (s === "today" ? today : s === "backlog" ? backlog : []);
  let ghostAt: { status: Status; index: number } | null = null;
  let collapsedId: string | null = null;
  if (dragged && dnd.over && dnd.over.status !== "done") {
    const list = listOf(dnd.over.status);
    const before = dnd.over.beforeId;
    const at = before ? list.findIndex((t) => t.id === before) : list.length;
    const from = list.findIndex((t) => t.id === dragged.id);
    const stays = from >= 0 && (at === from || at === from + 1);
    if (at >= 0 && !stays) {
      ghostAt = { status: dnd.over.status, index: at };
      if (from >= 0) collapsedId = dragged.id;
    }
  }

  const flags = (t: Task) => ({
    dim: !!filter && t.area !== filter,
    dragging: dnd.dragging === t.id,
    collapsed: collapsedId === t.id,
    completing: board.completing === t.id,
    arrived: board.arrived === t.id,
    landed: dnd.landed === t.id,
  });
  const flightOf = (t: Task) => (flight?.id === t.id ? flight : null);
  const now = new Date();
  const todayZone = dnd.zone("today");
  const backlogZone = dnd.zone("backlog");
  const doneZone = dnd.zone("done");

  /** Inserts the drag preview into a list. */
  const withGhost = (status: "today" | "backlog", cards: ReactNode[]) => {
    if (!dragged || ghostAt?.status !== status) return cards;
    const ghost = <GhostCard key="__ghost__" id={dragged.id} kind={status} title={dragged.title} tint={colourOf(dragged.area).tint} focus={dragged.focus} onDragOver={dnd.ghost.onDragOver} />;
    return [...cards.slice(0, ghostAt.index), ghost, ...cards.slice(ghostAt.index)];
  };

  return (
    <div className={inTauri ? "app desktop themed" : "app themed"} style={themeVars(theme)} onDragOver={dnd.outside.onDragOver}>
      {/* The window has no title bar; this invisible strip at the top lets you drag it around. */}
      {inTauri && <div className="titlebar" data-tauri-drag-region />}
      {board.error && <div className="error-bar">{board.error}</div>}
      <div className="page">
        <header className="header" data-tauri-drag-region>
          <div className="date">
            <span className="date-day num">{now.getDate()}</span>
            <div className="date-text">
              <span className="weekday">{now.toLocaleDateString("en-GB", { weekday: "long" })}</span>
              <span className="month">{now.toLocaleDateString("en-GB", { month: "long" })}</span>
            </div>
          </div>
          <div className="tools">
            {cats.map((c) => {
              const on = filter === c.id;
              const col = colourOf(c.id).strong;
              return (
                <button key={c.id} type="button" className="dotbtn" onClick={() => setFilter(on ? null : c.id)} aria-label={`Highlight ${c.name}`} aria-pressed={on} data-tip={c.name} style={{ width: 32, height: 44 }}>
                  <span className="dot" style={{ width: 12, height: 12, background: col, opacity: filter && !on ? 0.35 : 1, boxShadow: on ? `0 0 0 3px var(--bg), 0 0 0 4.5px ${col}` : "none" }} />
                </button>
              );
            })}
            <span className="divider themed" />
            <button type="button" className="iconbtn" onClick={() => setShowSettings((v) => !v)} aria-label="Settings" aria-expanded={showSettings} style={{ width: 44, height: 44, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <SlidersIcon />
            </button>
            <button type="button" className="plus" onClick={() => setQuick(true)} aria-label="Add task" title="Add task  ⌥ Space">
              <PlusIcon />
            </button>
            {showSettings && (
              <SettingsPopover settings={settings} board={board} colourOf={(id) => colourOf(id).strong}
                paletteColour={(k) => colours(theme, k).strong} onClose={() => setShowSettings(false)} />
            )}
          </div>
        </header>

        <div className="column">
          <section aria-label="Today" className={"section " + todayZone.className} onDragOver={todayZone.onDragOver} onDrop={todayZone.onDrop}>
            <div className="section-head themed">
              <h2>Today</h2>
              <span className="count num">{today.length}</span>
            </div>
            <div className="grid-today" ref={todayGrid} {...dnd.grid("today")}>
              {withGhost("today", today.map((t, i) => (
                <TodayCard key={t.id} task={t} strong={colourOf(t.area).strong} tint={colourOf(t.area).tint} catName={catOf(t.area)?.name ?? ""} flags={flags(t)}
                  dnd={dnd.card(t.id, "today", today[i + 1]?.id)} flight={flightOf(t)}
                  onOpen={() => setOpenId(t.id)} onCycleColour={() => board.cycleColour(t.id)}
                  onComplete={() => finish(t.id)} onToggleFocus={() => board.toggleFocus(t.id)} />
              )))}
              {today.length === 0 && !(dragged && dnd.over?.status === "today") && <div className="empty themed">Throw cards here</div>}
            </div>
          </section>

          {suggested.length > 0 && (
            <section aria-label="Suggested" className="suggested">
              <span className="cap">Suggested</span>
              {suggested.map((t) => (
                <div key={t.id} className="suggest-row themed">
                  <span className="dot" style={{ width: 8, height: 8, background: colourOf(t.area).strong, flex: "none" }} />
                  <button type="button" className="opener title" onClick={() => setOpenId(t.id)}>{t.title}</button>
                  {t.from && <span className="from mono" title={t.from}>{t.from.replace(/^\[\[|\]\]$/g, "").split("/").pop()}</span>}
                  <button type="button" className="iconbtn small-btn" onClick={() => board.accept(t.id)} style={{ color: "var(--ink)" }}>Accept</button>
                  <button type="button" className="iconbtn small-btn" onClick={() => board.remove(t.id)} title="Dismiss (deletes the file)">Dismiss</button>
                </div>
              ))}
            </section>
          )}

          <section aria-label="Backlog" className={"section " + backlogZone.className} onDragOver={backlogZone.onDragOver} onDrop={backlogZone.onDrop}>
            <div className="section-head themed">
              <h2>Backlog</h2>
              <span className="count num">{backlog.length}</span>
            </div>
            <div className="grid-backlog" ref={backlogGrid} {...dnd.grid("backlog")}>
              {withGhost("backlog", backlog.map((t, i) => (
                <BacklogCard key={t.id} task={t} strong={colourOf(t.area).strong} tint={colourOf(t.area).tint} catName={catOf(t.area)?.name ?? ""} flags={flags(t)}
                  dnd={dnd.card(t.id, "backlog", backlog[i + 1]?.id)} flight={flightOf(t)}
                  onOpen={() => setOpenId(t.id)} onCycleColour={() => board.cycleColour(t.id)}
                  onToToday={() => board.move(t.id, "today")} />
              )))}
            </div>
          </section>

          <section aria-label="Done" className={"done-zone " + doneZone.className} onDragOver={doneZone.onDragOver} onDrop={doneZone.onDrop} style={{ display: "flex", flexDirection: "column" }}>
            <button type="button" className="done-head themed" onClick={() => setDoneOpen((v) => !v)} aria-expanded={doneOpen}>
              <span ref={doneNum} className={board.bump ? "done-num num bump" : "done-num num"}>{doneToday.length}</span>
              <span className="done-label">
                <strong>Done today</strong>
                <span className="last">Last: {lastDone}</span>
              </span>
              <span style={{ marginBottom: 6 }}><ChevronIcon open={doneOpen} /></span>
            </button>
            {doneOpen && doneWeek.map((t) => (
              <div key={t.id} className="done-row themed">
                <span style={{ width: 32, display: "flex", justifyContent: "center" }}>
                  <span className="dot" style={{ width: 10, height: 10, background: colourOf(t.area).strong }} />
                </span>
                <span className="title">{t.title}</span>
                {!t.doneOn!.startsWith(todayStr()) && <span className="done-day">{dayLabel(t.doneOn!)}</span>}
                <button type="button" className="iconbtn reveal" onClick={() => board.move(t.id, "today")} style={{ height: 32, padding: "0 8px", fontSize: 12, fontWeight: 500, color: "var(--ink)" }}>Undo</button>
              </div>
            ))}
          </section>
        </div>
      </div>

      {openTask && (
        <DetailPanel
          task={openTask}
          categories={cats}
          colourOf={(id) => colourOf(id).strong}
          tasksFolder={settings.tasksFolder}
          onPatch={(p, soon) => board.patch(openTask.id, p, { soon })}
          onRename={(title) => { const old = openTask.id; board.rename(old, title).then((id) => setOpenId((cur) => (cur === old ? id : cur))); }}
          onMove={() => (openTask.status === "suggested" ? board.accept(openTask.id) : board.move(openTask.id, openTask.status === "today" ? "backlog" : "today"))}
          onDone={() => { const id = openTask.id; setOpenId(null); setTimeout(() => finish(id), 260); }}
          onOpenInObsidian={() => api.openInObsidian(openTask.id)}
          onClose={() => setOpenId(null)}
        />
      )}

      {quick && (
        <QuickAdd
          categories={cats}
          colourOf={(id) => colourOf(id).strong}
          initialColour={filter ?? cats[0]?.id ?? ""}
          onAdd={(title, area, status) => { board.add(title, area, status); setQuick(false); }}
          onClose={() => setQuick(false)}
        />
      )}
    </div>
  );
}
