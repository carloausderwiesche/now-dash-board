// Slides in from the right when you click a card's title.
// Everything here edits the task's .md file directly.

import { useEffect, useRef, useState } from "react";
import type { Category, Task } from "../types";
import { CloseIcon, ChevronIcon } from "./Icons";

interface Props {
  task: Task;
  categories: Category[];
  colourOf: (id: string) => string;
  tasksFolder: string;
  onPatch: (p: Partial<Task>, soon?: boolean) => void;
  /** Called when you finish editing the title (blur, Enter, or closing the panel): renames the file. */
  onRename: (title: string) => void;
  onMove: () => void;
  onDone: () => void;
  onOpenInObsidian: () => void;
  onClose: () => void;
}

/** Roughly what the file looks like (the real file also keeps any extra fields). */
function previewMarkdown(t: Task) {
  const lines = ["---", `status: ${t.status}`, `area: ${t.area}`, `order: ${t.order}`, `created: ${t.created ?? ""}`, `done: ${t.doneOn ?? ""}`];
  if (t.project) lines.push(`project: "${t.project}"`);
  if (t.from) lines.push(`from: "${t.from}"`);
  if (t.focus) lines.push("focus: true");
  lines.push("---");
  lines.push(...t.items.map((x) => `- [${x.done ? "x" : " "}] ${x.text}`));
  if (t.notes.trim()) { if (t.items.length) lines.push(""); lines.push(t.notes.trim()); }
  return lines.join("\n");
}

export function DetailPanel({ task, categories, colourOf, tasksFolder, onPatch, onRename, onMove, onDone, onOpenInObsidian, onClose }: Props) {
  const [newItem, setNewItem] = useState("");
  // The title is the file name, so it's edited locally and only renamed when you're done.
  const [title, setTitle] = useState(task.title);
  const titleRef = useRef({ title, saved: task.title, onRename });
  titleRef.current = { title, saved: task.title, onRename };
  useEffect(() => setTitle(task.title), [task.title]);
  const commitTitle = () => { const r = titleRef.current; if (r.title.trim() && r.title.trim() !== r.saved) r.onRename(r.title.trim()); };
  useEffect(() => () => commitTitle(), []); // closing the panel also commits
  const [showFile, setShowFile] = useState(false);
  const cat = categories.find((c) => c.id === task.area) ?? categories[0];
  const doneCount = task.items.filter((x) => x.done).length;
  const where = { today: "Today", backlog: "Backlog", done: "Done", suggested: "Suggested" }[task.status];

  const ringed = (id: string) => ({
    width: 14, height: 14, background: colourOf(id),
    boxShadow: id === task.area ? `0 0 0 3px var(--surface), 0 0 0 4.5px ${colourOf(id)}` : "none",
  });

  return (
    <>
      <div className="scrim" style={{ zIndex: 35 }} onClick={onClose} />
      <aside className="drawer themed" role="dialog" aria-label="Task details">
        <div className="drawer-strip" style={{ background: colourOf(task.area) }} />
        <div className="drawer-body">
          <div className="drawer-top">
            <div style={{ display: "flex", alignItems: "center" }}>
              {categories.map((c) => (
                <button key={c.id} type="button" className="dotbtn" onClick={() => onPatch({ area: c.id })} aria-label={c.name} aria-pressed={c.id === task.area} title={c.name} style={{ width: 32, height: 36 }}>
                  <span className="dot" style={ringed(c.id)} />
                </button>
              ))}
            </div>
            <span className="catname">{cat?.name}</span>
            <span style={{ flex: 1 }} />
            <button type="button" className="iconbtn" onClick={onClose} aria-label="Close" style={{ width: 44, height: 44, display: "flex", alignItems: "center", justifyContent: "center", marginRight: -12 }}>
              <CloseIcon />
            </button>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <label htmlFor="d-title" className="sr-only">Title</label>
            <textarea id="d-title" className="field drawer-title" rows={2} value={title}
              onChange={(e) => setTitle(e.target.value.replace(/\n/g, " "))}
              onBlur={commitTitle}
              onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); (e.target as HTMLTextAreaElement).blur(); } }} />
            {task.status !== "done" && (
              <div className="where">
                <span className="muted">In {where}</span>
                <span className="sep">·</span>
                <button type="button" className="iconbtn textlink" onClick={onMove}>
                  {task.status === "today" ? "Move to Backlog" : task.status === "suggested" ? "Accept" : "Move to Today"}
                </button>
              </div>
            )}
          </div>

          <div style={{ display: "flex", flexDirection: "column" }}>
            <div className="block-head themed">
              <span>Checklist</span>
              {task.items.length > 0 && <span className="count num">{doneCount} / {task.items.length}</span>}
            </div>
            {task.items.map((it, i) => (
              <label key={i} className="check-row themed">
                <input type="checkbox" className="ck" checked={it.done}
                  onChange={() => onPatch({ items: task.items.map((x, j) => (j === i ? { ...x, done: !x.done } : x)) })} />
                <span className={it.done ? "done-text" : ""} style={{ flex: 1 }}>{it.text}</span>
              </label>
            ))}
            <div className="add-row themed">
              <span className="plus-mark">+</span>
              <label htmlFor="d-new" className="sr-only">Add checklist item</label>
              <input id="d-new" className="field" value={newItem} placeholder="Add a step"
                onChange={(e) => setNewItem(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && newItem.trim()) {
                    e.preventDefault();
                    onPatch({ items: [...task.items, { text: newItem.trim(), done: false }] });
                    setNewItem("");
                  }
                }} />
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <label htmlFor="d-notes" style={{ fontSize: 15, fontWeight: 600 }}>Notes</label>
            <textarea id="d-notes" className="field notes themed" rows={4} value={task.notes} placeholder="Anything worth remembering"
              onChange={(e) => onPatch({ notes: e.target.value }, true)} />
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <button type="button" className="md-toggle mono" onClick={() => setShowFile((v) => !v)} aria-expanded={showFile}>
              <ChevronIcon open={showFile} />
              {tasksFolder}/{task.id}
            </button>
            {showFile && <pre className="md mono themed">{previewMarkdown(task)}</pre>}
          </div>
        </div>

        <div className="drawer-foot themed">
          {task.status !== "done" && task.status !== "suggested" && <button type="button" className="btn-primary" onClick={onDone}>Mark done</button>}
          <button type="button" className="btn-secondary themed" onClick={onOpenInObsidian}>Open in Obsidian</button>
        </div>
      </aside>
    </>
  );
}
