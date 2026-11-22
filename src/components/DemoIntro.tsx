// Only in the browser demo (e.g. the GitHub Pages site), never in the desktop
// app: a short explanation of what Nowboard is and what to try.

import { useState } from "react";
import { api } from "../api";
import { CloseIcon } from "./Icons";

const KEY = "nowboard-demo-intro-hidden";
const hiddenBefore = () => { try { return localStorage.getItem(KEY) === "1"; } catch { return false; } };

export function DemoIntro() {
  const [hidden, setHidden] = useState(hiddenBefore);
  if (hidden) return null;
  const hide = () => { setHidden(true); try { localStorage.setItem(KEY, "1"); } catch { /* private mode */ } };

  return (
    <aside className="demo-intro themed" aria-label="About this demo">
      <div className="demo-text">
        <strong>Nowboard is a calm board for what you're doing today.</strong>
        <span>
          It's a macOS app: every task is a plain markdown file in your Obsidian vault, so your tasks stay yours,
          sync like any note, and other tools (or an AI agent) can read and add them. This page is a clickable demo
          with sample tasks; changes are kept only in this browser.
        </span>
        <span className="demo-try">
          Try: tick a card's circle · drag cards between Today and Backlog · click a title for details · press N to add ·
          click the colour dots in the header to highlight a category · sliders icon for themes.
        </span>
        <span className="demo-links">
          <a href="https://github.com/nestoririondo/nowboard" target="_blank" rel="noreferrer">Source on GitHub</a>
          <span aria-hidden>·</span>
          <button type="button" className="iconbtn textlink" onClick={api.resetDemo}>Reset sample data</button>
        </span>
      </div>
      <button type="button" className="iconbtn demo-close" onClick={hide} aria-label="Hide this introduction"><CloseIcon /></button>
    </aside>
  );
}
