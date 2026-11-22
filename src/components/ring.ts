import type { CSSProperties } from "react";

/**
 * The ring around a selected colour dot. Drawn as an outline (not a box-shadow):
 * the gap stays see-through on any background, and WebKit doesn't trim it while
 * the dot is animating (it grows on hover), which made shadow rings look clipped.
 */
export const ring = (on: boolean, color: string): CSSProperties =>
  on ? { outline: `1.5px solid ${color}`, outlineOffset: 3 } : { outline: "none" };
