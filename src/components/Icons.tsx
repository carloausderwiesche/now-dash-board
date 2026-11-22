// Small stroke icons. They inherit the text colour (currentColor).

const base = { fill: "none", stroke: "currentColor", strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };

export const PlusIcon = ({ size = 20 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" strokeWidth={2.2} {...base}><path d="M12 5v14M5 12h14" /></svg>
);
export const SlidersIcon = () => (
  <svg width={18} height={18} viewBox="0 0 24 24" strokeWidth={1.7} {...base}>
    <path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" />
  </svg>
);
export const ChevronIcon = ({ open }: { open: boolean }) => (
  <svg className={open ? "chev open" : "chev"} width={14} height={14} viewBox="0 0 24 24" strokeWidth={2} {...base}><path d="M9 6l6 6-6 6" /></svg>
);
export const DownIcon = () => (
  <svg width={10} height={10} viewBox="0 0 24 24" strokeWidth={2.4} {...base}><path d="M6 9l6 6 6-6" /></svg>
);
export const CloseIcon = () => (
  <svg width={16} height={16} viewBox="0 0 24 24" strokeWidth={1.8} {...base}><path d="M6 6l12 12M18 6L6 18" /></svg>
);
/** "Focus on this now": a small target. */
export const FocusIcon = () => (
  <svg width={12} height={12} viewBox="0 0 24 24" strokeWidth={2.2} {...base}><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="2.5" /></svg>
);
export const PauseIcon = () => (
  <svg width={12} height={12} viewBox="0 0 24 24" strokeWidth={2.6} {...base}><path d="M9 6v12M15 6v12" /></svg>
);
/** Marks a `#private` task (the AI won't use it). */
export const LockIcon = ({ size = 12 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" strokeWidth={2} {...base}>
    <rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" />
  </svg>
);
/** The tick that draws itself inside the round check (see .tick in styles.css). */
export const Tick = ({ size = 13 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" strokeWidth={3.2} {...base} stroke="var(--onaccent)">
    <path className="tick" d="M5 12.5l4.5 4.5L19 7.5" />
  </svg>
);
