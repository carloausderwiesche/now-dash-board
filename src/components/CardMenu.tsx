// The menu you get when right-clicking a card. Drawn by the app (not the
// native macOS menu) so it matches the theme and can confirm Delete in place,
// see docs/adr/0004-themed-card-menu.md. What it contains comes from cardMenu.ts.

import { Fragment, useEffect, useLayoutEffect, useRef, useState, type ComponentType, type KeyboardEvent } from "react";
import { placeMenu, type CardMenuModel, type MenuIcon } from "../cardMenu";
import { ArrowIcon, CheckIcon, ExternalIcon, FocusIcon, PauseIcon, TrashIcon } from "./Icons";
import { ring } from "./ring";

const CONFIRM_MS = 4000; // same as the detail panel's "Delete file"

const ICONS: Record<MenuIcon, ComponentType> = {
  up: () => <ArrowIcon up />,
  down: () => <ArrowIcon up={false} />,
  focus: FocusIcon,
  pause: PauseIcon,
  done: CheckIcon,
  external: () => <ExternalIcon size={14} />,
  trash: () => <TrashIcon size={14} />,
};

export function CardMenu(p: { model: CardMenuModel; at: { x: number; y: number }; colourOf: (id: string) => string; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  const [armed, setArmed] = useState<string | null>(null);
  const [hoverCat, setHoverCat] = useState<string | null>(null);
  const returnTo = useRef(document.activeElement as HTMLElement | null);
  const onClose = useRef(p.onClose);
  onClose.current = p.onClose;

  /** Esc, a click elsewhere…: give focus back to where it was. After an action, the action decides. */
  const dismiss = () => {
    if (returnTo.current?.isConnected) returnTo.current.focus();
    onClose.current();
  };

  // Measure first, then place, so it never shows half off-screen.
  useLayoutEffect(() => {
    const el = ref.current!;
    setPos(placeMenu(p.at, { w: el.offsetWidth, h: el.offsetHeight }, { w: window.innerWidth, h: window.innerHeight }));
    // The menu itself takes focus, not its first item: like a macOS menu nothing is
    // highlighted until an arrow key (focusing the current category's dot drew a focus
    // ring around its selection ring). A frame later, because the right-click's own
    // mousedown moves focus to the card after this runs.
    const f = requestAnimationFrame(() => el.focus({ preventScroll: true }));
    return () => cancelAnimationFrame(f);
  }, [p.at]);

  useEffect(() => {
    const outside = (e: PointerEvent) => !ref.current?.contains(e.target as Node) && dismiss();
    const close = () => onClose.current();
    // Like a macOS menu, the page holds still while it's open. (Closing on scroll
    // instead would shut it at once when a trackpad is still gliding.)
    const holdStill = (e: WheelEvent) => e.preventDefault();
    document.addEventListener("pointerdown", outside, true);
    document.addEventListener("wheel", holdStill, { passive: false });
    window.addEventListener("blur", close);
    window.addEventListener("resize", close);
    return () => {
      document.removeEventListener("pointerdown", outside, true);
      document.removeEventListener("wheel", holdStill);
      window.removeEventListener("blur", close);
      window.removeEventListener("resize", close);
    };
  }, []);

  useEffect(() => {
    if (!armed) return;
    const t = window.setTimeout(() => setArmed(null), CONFIRM_MS);
    return () => window.clearTimeout(t);
  }, [armed]);

  const onKey = (e: KeyboardEvent) => {
    e.stopPropagation(); // the board's shortcuts (N, Esc closing the panel) don't apply while the menu is open
    if (e.key === "Escape" || e.key === "Tab") {
      e.preventDefault();
      dismiss();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "ArrowLeft" || e.key === "ArrowRight") {
      e.preventDefault();
      const items = [...ref.current!.querySelectorAll<HTMLElement>("[role^=menuitem]")];
      const i = items.indexOf(document.activeElement as HTMLElement);
      const step = e.key === "ArrowDown" || e.key === "ArrowRight" ? 1 : -1;
      const next = i < 0 ? (step > 0 ? 0 : items.length - 1) : (i + step + items.length) % items.length;
      items[next]?.focus();
    }
  };

  const shownCat = p.model.categories.find((c) => c.id === hoverCat) ?? p.model.categories.find((c) => c.current);
  return (
    <div
      ref={ref}
      role="menu"
      aria-label="Card"
      tabIndex={-1}
      className="card-menu themed"
      style={pos ? { left: pos.x, top: pos.y } : { visibility: "hidden" }}
      onKeyDown={onKey}
      onContextMenu={(e) => e.preventDefault()}
    >
      <div className="menu-cats">
        {p.model.categories.map((c) => (
          <button
            key={c.id}
            type="button"
            role="menuitemradio"
            aria-checked={c.current}
            aria-label={c.name}
            className="dotbtn"
            onClick={c.action}
            onMouseEnter={() => setHoverCat(c.id)}
            onMouseLeave={() => setHoverCat(null)}
            onFocus={() => setHoverCat(c.id)}
            onBlur={() => setHoverCat(null)}
          >
            <span className="dot" style={{ width: 12, height: 12, background: p.colourOf(c.id), ...ring(c.current, p.colourOf(c.id)) }} />
          </button>
        ))}
        <span className="menu-catname">{shownCat?.name}</span>
      </div>
      {p.model.groups.map((group, g) => (
        <Fragment key={g}>
          <div className="menu-sep" role="separator" />
          {group.map((item) => {
            const Icon = item.icon && ICONS[item.icon];
            const isArmed = armed === item.text;
            return (
              <button
                key={item.text}
                type="button"
                role="menuitem"
                className={["menu-row", item.confirm && "danger", isArmed && "armed"].filter(Boolean).join(" ")}
                onClick={() => {
                  if (item.confirm && !isArmed) return setArmed(item.text);
                  item.action();
                  onClose.current();
                }}
              >
                <span aria-live={item.confirm ? "polite" : undefined}>{isArmed ? item.confirm : item.text}</span>
                {Icon && (
                  <span className="menu-icon">
                    <Icon />
                  </span>
                )}
                {isArmed && <span className="menu-drain" />}
              </button>
            );
          })}
        </Fragment>
      ))}
    </div>
  );
}
