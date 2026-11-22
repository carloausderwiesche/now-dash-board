// Every colour, radius and font lives here. Components only use CSS
// variables (var(--ink), var(--R) …), so a theme switch is one style change.

import type { CSSProperties } from "react";
import type { PaletteKey, ThemeKey } from "./types";

interface Theme {
  name: string;
  group: "Rams" | "Ive" | "Pastel";
  bg: string;
  surface: string;
  well: string;
  hover: string;
  ink: string;
  muted: string;
  line: string;
  accent: string;
  onaccent: string;
  scrim: string;
  style: "rams" | "ive" | "pastel";
  dark: boolean;
}

export const THEMES: Record<ThemeKey, Theme> = {
  braun:     { name: "Braun",      group: "Rams",   bg: "#ECEAE4", surface: "#F8F7F4", well: "#E0DDD5", hover: "rgba(0,0,0,.035)",       ink: "#1B1B1A", muted: "#57554F", line: "#D5D2CA",            accent: "#E5541B", onaccent: "#FFFFFF", scrim: "rgba(40,38,34,.28)",    style: "rams",   dark: false },
  graphite:  { name: "Graphite",   group: "Rams",   bg: "#1D1D1C", surface: "#272725", well: "#2E2E2C", hover: "rgba(255,255,255,.04)",  ink: "#EDEBE6", muted: "#A19F99", line: "#3B3A37",            accent: "#F26B2F", onaccent: "#1D1D1C", scrim: "rgba(0,0,0,.5)",        style: "rams",   dark: true },
  aluminium: { name: "Aluminium",  group: "Ive",    bg: "#F5F5F7", surface: "#FFFFFF", well: "#E8E8ED", hover: "rgba(0,0,0,.035)",       ink: "#1D1D1F", muted: "#5E5E63", line: "rgba(0,0,0,.09)",    accent: "#0071E3", onaccent: "#FFFFFF", scrim: "rgba(245,245,247,.6)",  style: "ive",    dark: false },
  spacegrey: { name: "Space Grey", group: "Ive",    bg: "#161617", surface: "#2C2C2E", well: "#2C2C2E", hover: "rgba(255,255,255,.05)",  ink: "#F5F5F7", muted: "#A1A1A6", line: "rgba(255,255,255,.1)", accent: "#2997FF", onaccent: "#FFFFFF", scrim: "rgba(0,0,0,.45)",       style: "ive",    dark: true },
  peach:     { name: "Peach",      group: "Pastel", bg: "#FBF1EA", surface: "#FFFAF6", well: "#F3E3D8", hover: "rgba(0,0,0,.03)",        ink: "#3B2A22", muted: "#5E4A3D", line: "#EEDDD1",            accent: "#EE8E62", onaccent: "#3B2A22", scrim: "rgba(59,42,34,.18)",    style: "pastel", dark: false },
  mint:      { name: "Mint",       group: "Pastel", bg: "#EAF5EF", surface: "#F7FCF9", well: "#D9ECE1", hover: "rgba(0,0,0,.03)",        ink: "#1F3A2E", muted: "#43594D", line: "#D3E8DC",            accent: "#3FAE82", onaccent: "#FFFFFF", scrim: "rgba(31,58,46,.18)",    style: "pastel", dark: false },
  lavender:  { name: "Lavender",   group: "Pastel", bg: "#F1EEFA", surface: "#FBFAFF", well: "#E4DFF4", hover: "rgba(0,0,0,.03)",        ink: "#2B2640", muted: "#524C6B", line: "#E2DCF3",            accent: "#8B74E8", onaccent: "#FFFFFF", scrim: "rgba(43,38,64,.2)",     style: "pastel", dark: false },
};

const STYLE = {
  rams:   { r: "4px",  R: "8px",  card: "4px",  font: "Inter, 'Helvetica Neue', Helvetica, Arial, sans-serif" },
  ive:    { r: "10px", R: "20px", card: "12px", font: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, 'Helvetica Neue', Arial, sans-serif" },
  pastel: { r: "10px", R: "18px", card: "12px", font: "Inter, 'Helvetica Neue', Arial, sans-serif" },
};

/** [strong colour for dots, soft tint for Today cards], per light/dark mode. */
/** In hue order: this is also the order of the swatches in the colour picker. */
export const PALETTE: Record<PaletteKey, { light: [string, string]; dark: [string, string] }> = {
  rose:   { light: ["#D6456C", "#F9DCE4"], dark: ["#FF8FB0", "#46262F"] },
  red:    { light: ["#D23B2E", "#F9DDD9"], dark: ["#FF8A7F", "#47231F"] },
  orange: { light: ["#D2621A", "#FBE3D1"], dark: ["#FFA466", "#46301C"] },
  amber:  { light: ["#C98512", "#FAEBCB"], dark: ["#FFC266", "#45361C"] },
  green:  { light: ["#2E8B3E", "#D9EFDC"], dark: ["#7FD98E", "#1D3A23"] },
  teal:   { light: ["#138A7E", "#D3EFEA"], dark: ["#6FE0CF", "#17383A"] },
  cyan:   { light: ["#0E85A6", "#D2ECF3"], dark: ["#6BD3F0", "#16343E"] },
  blue:   { light: ["#2F6BDB", "#DCE7FB"], dark: ["#7FAAFF", "#1F3050"] },
  indigo: { light: ["#4B4FC9", "#E0E1F8"], dark: ["#9EA1FF", "#262850"] },
  violet: { light: ["#7A55D6", "#E6DDFA"], dark: ["#B9A2FF", "#30284A"] },
  pink:   { light: ["#C2408F", "#F7DCEC"], dark: ["#FF8DD0", "#44253A"] },
  brown:  { light: ["#8A5A3B", "#EEE2D8"], dark: ["#D2A685", "#3A2C22"] },
  slate:  { light: ["#5D6470", "#E3E5E9"], dark: ["#B4BAC6", "#2C3038"] },
};
export const PALETTE_KEYS = Object.keys(PALETTE) as PaletteKey[];

export function themeVars(key: ThemeKey): CSSProperties {
  const t = THEMES[key] ?? THEMES.braun;
  const s = STYLE[t.style];
  return {
    "--bg": t.bg, "--surface": t.surface, "--well": t.well, "--hover": t.hover,
    "--ink": t.ink, "--muted": t.muted, "--line": t.line,
    "--accent": t.accent, "--onaccent": t.onaccent, "--scrim": t.scrim,
    "--r": s.r, "--R": s.R, "--card": s.card, "--font": s.font,
  } as CSSProperties;
}

export function colours(key: ThemeKey, palette: PaletteKey): { strong: string; tint: string } {
  const mode = THEMES[key]?.dark ? "dark" : "light";
  const [strong, tint] = (PALETTE[palette] ?? PALETTE.slate)[mode];
  return { strong, tint };
}
