import { useEffect, useRef, useState } from "react";
import { api, inTauri } from "./api";
import { byOrder, todayStr } from "./board";
import { colours, themeVars } from "./themes";
import { useBoard } from "./useBoard";
import { useDnd } from "./useDnd";
import { useFlip } from "./useFlip";
import { BacklogCard, GhostCard, TodayCard, type Flight } from "./components/Cards";
import { DetailPanel } from "./components/DetailPanel";
import { Header } from "./components/Header";
import { QuickAdd } from "./components/QuickAdd";
import { CardSection, DoneSection, SuggestedSection } from "./components/Sections";
import { SettingsPopover } from "./components/SettingsPopover";
import { DemoIntro } from "./components/DemoIntro";
import type { Status, Task, ThemeKey } from "./types";

const PANEL_CLOSE_MS = 260; // "Done" in the detail panel: let the panel close before the card flies

export default function App() {
  const board = useBoard();
  const { tasks, settings } = board;
  const [filter, setFilter] = useState<string | null>(null);
  const [quick, setQuick] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  const [showSettings, setShowSettings] = useState(false);
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
      const a = card.getBoundingClientRect(),
        b = target.getBoundingClientRect();
      // If Done is below the fold, aim for the bottom edge of the window instead.
      const tx = b.left + b.width / 2,
        ty = Math.min(b.top + b.height / 2, window.innerHeight - 24);
      setFlight({ id, x: tx - (a.left + a.width / 2), y: ty - (a.top + a.height / 2) });
    }
    board.complete(id);
  };

  // Finished in Obsidian or by an agent → same animation, one card at a time.
  const nextIncoming = board.incoming[0];
  useEffect(() => {
    if (nextIncoming && !board.completing) finish(nextIncoming);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `finish` is recreated every render; only these two should trigger it
  }, [nextIncoming, board.completing]);

  const dnd = useDnd((id, target) => {
    if (target.status === "done") finish(id);
    else board.move(id, target.status, target.beforeId, { quiet: true });
  });

  // N (inside the app) opens quick add; Esc closes things.
  // (⌥ Space from anywhere opens the separate quick window, see QuickWindow.tsx.)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing =
        e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLSelectElement;
      if (e.key === "Escape") {
        setOpenId(null);
        setShowSettings(false);
        setQuick(false);
      } else if (!typing && (e.key === "n" || (e.altKey && e.code === "Space"))) {
        e.preventDefault();
        setQuick(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // No vault configured yet → open settings so the first step is obvious.
  useEffect(() => {
    if (board.error && settings && !settings.vaultPath) setShowSettings(true);
  }, [board.error, settings]);

  // Put the theme's variables on <html> too, so the page background fills the
  // whole window (also when you scroll or drag past the top or bottom edge).
  const themeKey = settings?.theme as ThemeKey | undefined;
  useEffect(() => {
    if (!themeKey) return;
    const root = document.documentElement.style;
    Object.entries(themeVars(themeKey)).forEach(([k, v]) => root.setProperty(k, String(v)));
  }, [themeKey]);
  // Compact cards: one class on <html>, the sizes live in styles.css.
  const compact = !!settings?.compact;
  useEffect(() => {
    document.documentElement.classList.toggle("compact", compact);
  }, [compact]);

  if (!settings) return null;
  const theme = settings.theme as ThemeKey;
  const cats = settings.categories;
  const catOf = (id: string) => cats.find((c) => c.id === id) ?? cats[0];
  const colourOf = (id: string) => colours(theme, catOf(id)?.color ?? "slate");
  const strongOf = (id: string) => colourOf(id).strong;

  const inList = (s: Status) => tasks.filter((t) => t.status === s).sort(byOrder);
  const today = inList("today"),
    backlog = inList("backlog"),
    suggested = inList("suggested");
  // The big number counts today; the list shows the last 7 days, newest first.
  // Older done tasks stay on disk as history.
  const weekAgo = new Date(Date.now() - 6 * 864e5).toLocaleDateString("sv-SE");
  const doneWeek = tasks
    .filter((t) => t.status === "done" && t.doneOn && t.doneOn.slice(0, 10) >= weekAgo)
    .sort((a, b) => (b.doneOn ?? "").localeCompare(a.doneOn ?? "") || byOrder(a, b));
  const doneToday = doneWeek.filter((t) => t.doneOn?.startsWith(todayStr()));
  const openTask = tasks.find((t) => t.id === openId);
  const dragged = tasks.find((t) => t.id === dnd.dragging);

  /** Everything a Today or Backlog section needs: cards, drag preview, heading note, empty state. */
  const section = (status: "today" | "backlog", list: Task[], empty: { title: string; hint: string }) => {
    const preview = dnd.preview(
      status,
      list.map((t) => t.id),
    );
    const cards = list.map((t) => {
      const props = {
        task: t,
        strong: strongOf(t.area),
        tint: colourOf(t.area).tint,
        catName: catOf(t.area)?.name ?? "",
        flags: {
          dim: !!filter && t.area !== filter,
          dragging: dnd.dragging === t.id,
          collapsed: !!preview?.collapse && dnd.dragging === t.id,
          completing: board.completing === t.id,
          arrived: board.arrived === t.id,
          landed: dnd.landed === t.id,
          open: openId === t.id,
        },
        dnd: dnd.card(t.id, status),
        flight: flight?.id === t.id ? flight : null,
        onOpen: () => setOpenId(t.id),
        onCycleColour: () => board.cycleColour(t.id),
      };
      return status === "today" ? (
        <TodayCard key={t.id} {...props} onComplete={() => finish(t.id)} onToggleFocus={() => board.toggleFocus(t.id)} />
      ) : (
        <BacklogCard key={t.id} {...props} onToToday={() => board.move(t.id, "today")} />
      );
    });
    const ghost =
      dragged && preview
        ? {
            index: preview.index,
            node: (
              <GhostCard
                key="__ghost__"
                id={dragged.id}
                kind={status}
                title={dragged.title}
                tint={colourOf(dragged.area).tint}
                focus={dragged.focus}
              />
            ),
          }
        : null;
    // While a category is highlighted: a quiet note when this list has none of it.
    const none = !!filter && list.length > 0 && !list.some((t) => t.area === filter);
    const label = status === "today" ? "Today" : "Backlog";
    return {
      status,
      label,
      cards,
      ghost,
      zoneClass: dnd.zoneClass(status),
      note: none ? `No ${catOf(filter!)?.name} tasks ${status === "today" ? "today" : "in Backlog"}` : null,
      empty: list.length === 0 && !dnd.isOver(status) ? empty : null,
    };
  };

  return (
    <div
      className={["app", "themed", inTauri && "desktop", dnd.dragging && "is-dragging"].filter(Boolean).join(" ")}
      style={themeVars(theme)}
    >
      {/* The window has no title bar; this invisible strip at the top lets you drag it around. */}
      {inTauri && <div className="titlebar" data-tauri-drag-region />}
      {board.error && <div className="error-bar">{board.error}</div>}
      <div className="page">
        {!inTauri && <DemoIntro />}
        <Header
          categories={cats}
          filter={filter}
          onFilter={setFilter}
          colourOf={strongOf}
          settingsOpen={showSettings}
          onToggleSettings={() => setShowSettings((v) => !v)}
          onAdd={() => setQuick(true)}
        >
          {showSettings && (
            <SettingsPopover
              settings={settings}
              board={board}
              colourOf={strongOf}
              paletteColour={(k) => colours(theme, k).strong}
              onClose={() => setShowSettings(false)}
            />
          )}
        </Header>

        <div className="column">
          <CardSection
            gridRef={todayGrid}
            {...section("today", today, { title: "Nothing planned for today", hint: "Drag a card up from Backlog, or press N to add one" })}
          />
          <SuggestedSection tasks={suggested} colourOf={strongOf} onOpen={setOpenId} onAccept={board.accept} onDismiss={board.remove} />
          <CardSection
            gridRef={backlogGrid}
            {...section("backlog", backlog, {
              title: "Backlog is empty",
              hint: "Things for later wait here until you pull them into Today",
            })}
          />
          <DoneSection
            zoneClass={dnd.zoneClass("done")}
            week={doneWeek}
            todayCount={doneToday.length}
            lastDone={board.lastDone ?? doneToday[0]?.title ?? null}
            bump={board.bump}
            numRef={doneNum}
            colourOf={strongOf}
            onUndo={(id) => board.move(id, "today")}
          />
        </div>
      </div>

      {openTask && (
        <DetailPanel
          task={openTask}
          categories={cats}
          colourOf={strongOf}
          tasksFolder={settings.tasksFolder}
          onPatch={(p, soon) => board.patch(openTask.id, p, { soon })}
          onRename={(title) => {
            const old = openTask.id;
            board.rename(old, title).then((id) => setOpenId((cur) => (cur === old ? id : cur)));
          }}
          onMove={() =>
            openTask.status === "suggested"
              ? board.accept(openTask.id)
              : board.move(openTask.id, openTask.status === "today" ? "backlog" : "today")
          }
          onDone={() => {
            const id = openTask.id;
            setOpenId(null);
            setTimeout(() => finish(id), PANEL_CLOSE_MS);
          }}
          onOpenInObsidian={() => api.openInObsidian(openTask.id)}
          onDelete={() => {
            const id = openTask.id;
            setOpenId(null);
            board.remove(id);
          }}
          onClose={() => setOpenId(null)}
        />
      )}

      {quick && (
        <QuickAdd
          categories={cats}
          colourOf={strongOf}
          initialColour={filter ?? cats[0]?.id ?? ""}
          onAdd={(title, area, status) => {
            board.add(title, area, status);
            setQuick(false);
          }}
          onClose={() => setQuick(false)}
        />
      )}
    </div>
  );
}
