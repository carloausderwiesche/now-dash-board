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

// The same page runs in two windows: the board, and the small quick-add
// window that ⌥ Space opens from anywhere.
ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    {isQuickWindow ? <QuickWindow /> : <App />}
  </React.StrictMode>,
);
