import React from "react";
import ReactDOM from "react-dom/client";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/500.css";
import "./styles.css";
import App from "./App";
import { isQuickWindow } from "./api";
import { QuickWindow } from "./QuickWindow";
import { ErrorBoundary } from "./components/ErrorBoundary";

// No web-page menu (Reload, Inspect Element) on right-click. Only text you can
// select (same list as the user-select rule in styles.css) keeps the system
// menu for Copy, Paste and spelling. Cards open their own menu, see CardMenu.tsx.
document.addEventListener("contextmenu", (e) => {
  if (!(e.target as Element).closest?.("input, textarea, [contenteditable], .md, .snippet, .error-bar")) e.preventDefault();
});

// The same page runs in two windows: the board, and the small quick-add
// window that ⌥ Space opens from anywhere.
ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ErrorBoundary>{isQuickWindow ? <QuickWindow /> : <App />}</ErrorBoundary>
  </React.StrictMode>,
);
