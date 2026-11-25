// The cards, measured from src/styles.css (.today-card, .backlog-card,
// .card-foot, .ring). Today cards are big and tinted with their category
// colour; the focus card is ink-coloured and twice as wide; Backlog cards are
// small and plain. Title on top; the category dot bottom-left and the round
// check bottom-right.
//
// What you can do with a card (DESIGN.md, Interactions): tap the title to
// open it, the dot to change its category, the ring to finish it; Focus /
// Pause and "Today ↑" buttons; right-click (Mac) or long-press (iPhone) for
// the card menu.

import NowboardKit
import SwiftUI

enum CardStyle {
    case today, backlog
}

/// How a card is drawn: on the board, as the copy that follows the pointer
/// while dragging, or as the faded preview where it will land.
enum CardMode {
    case normal, clone, ghost
}

struct CardView: View {
    @Environment(BoardStore.self) private var store
    let task: BoardTask
    let style: CardStyle
    var mode: CardMode = .normal

    /// The pointer is over the card (Mac): lifts it and shows Focus / Today ↑.
    @State private var hovering = false
    /// The pointer is over the round check: shows a faint tick, hides Focus.
    @State private var overRing = false
    /// Going into focus, the card swells a little and settles (see `breathe()`).
    @State private var swelling = false

    /// The finish animation, if this card is playing it (BoardStore.finish).
    private var finish: Finish? { mode == .normal ? store.finishing[task.id] : nil }
    private var finishing: FinishStep { finish?.step ?? .idle }
    /// Being deleted: shrinks a little, blurs and fades where it stands, so it
    /// never looks like finishing (which goes down into Done).
    private var deleting: Bool { mode == .normal && store.deleting.contains(task.id) }

    var body: some View {
        let theme = store.theme
        let cat = category(for: task.area, in: store.settings.categories)
        let focus = style == .today && task.focus
        let density = store.settings.density
        // `switch` as an expression picks the measurements for this kind of card.
        let m: Metrics =
            switch (style, focus) {
            case (.backlog, _): .backlog(density)
            case (.today, true): .focus(density)
            case (.today, false): .today(density)
            }
        let ink = focus ? theme.bg : theme.ink
        let dragging = store.drag.id != nil
        // The open card menu covers the card, but it should still look pointed at.
        let isHovered = hovering || debugHover || store.menu?.id == task.id
        let isOverRing = overRing || (debugHover && debugRing)
        // .card:hover and .card.open lift the card 3pt; never while dragging.
        let lifted = mode == .normal && !dragging && finishing == .idle && (isHovered || store.openID == task.id)
        let shape = RoundedRectangle(cornerRadius: style == .today ? theme.radiusCard : theme.radiusSmall)

        let reveal = showReveal(hovering: isHovered, overRing: isOverRing)
        Group {
            // Minimal: one row, with the title between the dot and the ring.
            if density == .minimal {
                footer(m, cat: cat, focus: focus, density: density, theme: theme, reveal: reveal, overRing: isOverRing) {
                    title(m, density: density, theme: theme)
                }
            } else {
                VStack(alignment: .leading, spacing: m.gap) {
                    title(m, density: density, theme: theme)
                    Spacer(minLength: 0)
                    footer(m, cat: cat, focus: focus, density: density, theme: theme, reveal: reveal, overRing: isOverRing) {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.top, m.padTop)
        .padding(.horizontal, m.padSide)
        .padding(.bottom, m.padBottom)
        .frame(maxWidth: .infinity, minHeight: m.minHeight, maxHeight: .infinity,
               alignment: density == .minimal ? .leading : .topLeading)
        .background {
            switch (style, focus) {
            // One fill whose colour changes, so going into focus *blends* the
            // tint into ink instead of swapping one shape for another.
            case (.today, _): shape.fill(focus ? theme.ink : cat.color.tint(in: theme))
            case (.backlog, _): shape.fill(theme.surface).overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            }
        }
        // Shadows from the CSS, with its negative spread (CSSLike.swift):
        // the focus card always (0 14px 34px -16px .55), others when lifted
        // (0 14px 30px -16px .35), the dragged copy (0 18px 40px -14px .4).
        .cssShadow(y: 14, blur: 34, spread: -16, opacity: 0.55, radius: theme.radiusCard,
                   visible: focus && mode != .ghost)
        .cssShadow(y: 14, blur: 30, spread: -16, opacity: 0.35, radius: theme.radiusCard,
                   visible: lifted && !focus)
        .cssShadow(y: 18, blur: 40, spread: -14, opacity: 0.4, radius: theme.radiusCard, visible: mode == .clone)
        // The 3pt lift. `visualEffect` moves only what's drawn, not the area
        // that reacts to the pointer, so pointing at the bottom edge can't lift
        // the card off the pointer and drop it back in a loop.
        .visualEffect { content, _ in content.offset(y: lifted ? -3 : 0) }
        // Focus: a short breath while it grows.
        .scaleEffect(swelling ? 1.035 : deleting ? 0.88 : 1)
        .blur(radius: deleting ? 6 : 0)
        .modifier(FlyIntoDone(progress: finishing == .leaving ? 1 : 0, to: finish?.flight ?? .zero))
        .onChange(of: task.focus) { _, on in
            if on && style == .today && mode == .normal { breathe() }
        }
        // iPhone: a firm tap as the card comes into focus.
        .sensoryFeedback(.impact(weight: .medium), trigger: task.focus) { _, on in on }
        .opacity(opacity(dragging: dragging))
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.25), value: lifted)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // The section brings the hovered card to the front, so its tooltips
            // aren't hidden under the neighbouring cards.
            if inside {
                store.hoveredID = task.id
            } else if store.hoveredID == task.id {
                store.hoveredID = nil
            }
        }
        .cursor(.openHand)
        .allowsHitTesting(mode == .normal && finishing == .idle && !deleting)
        #if os(iOS)
            // Long-press: the system menu, which lifts the card (ADR 0012).
            // The Mac draws its own on a right-click (CardMenuPopup.swift).
            .contextMenu { CardMenu(task: task) }
        #endif
        // A small tap on the phone as the finished card leaves for Done.
        .sensoryFeedback(.success, trigger: finishing == .leaving) { _, leaving in leaving }
        .accessibilityElement(children: .contain)
    }

    /// The title (opens the panel) and the checklist count under it.
    private func title(_ m: Metrics, density: CardDensity, theme: Theme) -> some View {
        Button {
            guard !store.drag.swallowsClick else { return }
            store.openID = task.id
        } label: {
            VStack(alignment: .leading, spacing: density == .roomy ? 6 : 4) {
                TitleText(task: task, size: m.titleSize, weight: m.titleWeight, lines: m.lines, theme: theme,
                          struck: finishing != .idle,
                          tips: mode == .normal && store.drag.id == nil && finishing == .idle,
                          inverted: style == .today && task.focus, debugHover: debugHover)
                if style == .today && !task.items.isEmpty && density != .minimal {
                    Text("\(task.items.filter(\.done).count) / \(task.items.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pointer)
        .accessibilityLabel(task.title)
        .accessibilityHint("Opens the task")
    }

    /// .card-foot: the dot, (NOW), `middle` (a spacer, or the title on minimal
    /// cards), Focus / Today ↑, the ring.
    private func footer(_ m: Metrics, cat: Category, focus: Bool, density: CardDensity, theme: Theme, reveal: Bool,
                        overRing isOverRing: Bool, @ViewBuilder middle: () -> some View) -> some View {
        HStack(spacing: 2) {
            DotButton(color: cat.color.strong(in: theme), name: cat.name, box: m.dotBox, inverted: focus) {
                guard !store.drag.swallowsClick else { return }
                store.cycleCategory(task.id)
            }
            .padding(.leading, style == .today ? -8 : -7)
            if focus {
                Text("NOW")
                    .font(theme.font(11, .semibold))
                    .tracking(Theme.tracking(0.14, size: 11))
                    .opacity(0.8)
                    // Slides out of the dot a moment after the card starts growing.
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -8)).animation(.easeOut(duration: 0.35).delay(0.18)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))))
            }
            middle()
                .frame(maxWidth: .infinity, alignment: .leading)
            revealButton(theme: theme)
                .opacity(reveal ? 1 : 0)
                // Minimal: no room kept for it, so the one-line title gets the space.
                .fixedSize()
                .frame(width: density == .minimal && !reveal ? 0 : nil, alignment: .leading)
                .clipped()
                // Shows after 0.12s (so passing through doesn't flash it), hides at once.
                .animation(.easeOut(duration: 0.15).delay(reveal ? 0.12 : 0), value: reveal)
                .allowsHitTesting(reveal)
            if style == .today {
                Button {
                    guard !store.drag.swallowsClick else { return }
                    store.finish(task.id)
                } label: {
                    CheckRing(size: 22, step: finishing, hover: isOverRing, theme: theme)
                        .frame(width: 40, height: [.roomy: 40, .compact: 34, .minimal: 32][density]!)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pointer)
                .onHover { h in withAnimation(.easeOut(duration: 0.2)) { overRing = h } }
                .padding(.trailing, -8)
                .accessibilityLabel("Mark done")
            }
        }
    }

    private func opacity(dragging: Bool) -> Double {
        if deleting { return 0 }
        switch mode {
        case .clone: return 0.96
        case .ghost: return 0.45
        case .normal:
            // The dragged card's own slot is the preview: it fades.
            if store.drag.id == task.id { return 0.45 }
            // Highlighting a category fades the others to 22%.
            if let f = store.filter, f != task.area { return 0.22 }
            return 1
        }
    }

    /// Debug screenshots: `-hover <file name>` shows this card as hovered,
    /// `-hoverring true` also points at its ring.
    private var debugHover: Bool {
        #if DEBUG
            DebugSnapshot.argument("hover") == task.id && mode == .normal
        #else
            false
        #endif
    }

    private var debugRing: Bool {
        #if DEBUG
            DebugSnapshot.argument("hoverring") == "true"
        #else
            false
        #endif
    }

    /// Focus / Today ↑: on hover (after a moment), not while pointing at the
    /// ring, never while dragging. Always shown on a phone (CSS narrow rule).
    private func showReveal(hovering: Bool, overRing: Bool) -> Bool {
        guard mode == .normal, finishing == .idle, store.drag.id == nil else { return false }
        #if os(iOS)
            return true
        #else
            return hovering && !overRing
        #endif
    }

    @ViewBuilder
    private func revealButton(theme: Theme) -> some View {
        switch style {
        case .today:
            RevealButton(text: task.focus ? "Pause" : "Focus", icon: task.focus ? .pause : .focus, height: 32, padding: 8, theme: theme) {
                store.toggleFocus(task.id)
            }
            .help(task.focus ? "Stop focusing on this" : "Focus on this now")
        case .backlog:
            RevealButton(text: "Today ↑", icon: nil, height: 28, padding: 6, theme: theme) {
                store.moveToTop(task.id, of: .today)
            }
            .foregroundStyle(theme.ink)
        }
    }

    /// The swell: up quickly (0.18s), then a spring brings it back to size
    /// while the width is still growing, so the two blend into one organic motion.
    private func breathe() {
        withAnimation(.easeOut(duration: 0.18)) { swelling = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { swelling = false }
        }
    }
}

/// A finished card's way into the Done number: one smooth move on a gentle
/// curve (down first, then across, like something dropped in), only ever
/// shrinking and fading, with no lift or bounce.
///
/// Swift note: `Animatable` makes SwiftUI call `body` for every in-between
/// `progress` (0 → 1), so the card can follow a curve instead of a straight line.
struct FlyIntoDone: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    /// From the card's centre to the Done number's.
    let to: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress, u = 1 - progress
        // A quadratic Bézier curve from the card to `to`, pulled towards a
        // point below the card, so the path bends instead of cutting across.
        let bend = CGPoint(x: to.width * 0.15, y: to.height * 0.8)
        content
            .scaleEffect(1 - 0.9 * t)
            .offset(x: 2 * u * t * bend.x + t * t * to.width, y: 2 * u * t * bend.y + t * t * to.height)
            // Mostly there for the first 60% of the way, then gone (the CSS `fly` keyframes).
            .opacity(t < 0.6 ? 1 - 0.25 * t : 0.85 * (1 - t) / 0.4)
    }
}

/// A category dot you can click (.dotbtn): grows ×1.4 on hover with a little
/// overshoot, shrinks to ×0.8 while pressed, and shows the category's name
/// in a tooltip right away.
struct DotButton: View {
    let color: Color
    let name: String
    var box: CGFloat = 32
    var boxHeight: CGFloat? = nil
    var size: CGFloat = 10
    var inverted = false
    /// The selected category gets a ring: 1.5pt, 3pt away from the dot.
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle().fill(color).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(color, lineWidth: 1.5).padding(-4.5).opacity(selected ? 1 : 0))
                .scaleEffect(hovering ? 1.4 : 1)
                // cubic-bezier(0.2, 1.8, 0.4, 1) over 0.3s: a quick grow with a small overshoot.
                .animation(.timingCurve(0.2, 1.8, 0.4, 1, duration: 0.3), value: hovering)
                .frame(width: box, height: boxHeight ?? box)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(pressed: 0.8))
        .onHover { hovering = $0 }
        .tip(name, inverted: inverted)
        .cursor(.pointingHand)
        .accessibilityLabel("\(name), change category")
    }
}

/// Shrinks a button's label while it's pressed (CSS `:active { transform: scale(…) }`).
struct PressScale: ButtonStyle {
    var pressed: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressed : 1)
            .animation(.timingCurve(0.2, 1.8, 0.4, 1, duration: 0.3), value: configuration.isPressed)
    }
}

/// The card buttons ("Focus ◎", "Pause ‖", "Today ↑"): text plus a small
/// icon, in the card's text colour, underlined on hover (.iconbtn.reveal).
private struct RevealButton: View {
    enum Icon { case focus, pause }
    let text: String
    let icon: Icon?
    let height: CGFloat
    let padding: CGFloat
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(text).underline(hovering)
                switch icon {
                case .focus: FocusIcon().stroke(style: StrokeStyle(lineWidth: 2.2 * 12 / 24, lineCap: .round)).frame(width: 12, height: 12)
                case .pause: PauseIcon().stroke(style: StrokeStyle(lineWidth: 2.6 * 12 / 24, lineCap: .round)).frame(width: 12, height: 12)
                case nil: EmptyView()
                }
            }
            .font(theme.font(12, .medium))
            .frame(height: height)
            .padding(.horizontal, padding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pointer)
        .onHover { hovering = $0 }
    }
}

/// `<circle r=8/><circle r=2.5/>` on a 24×24 grid (Icons.tsx FocusIcon).
/// Icon stroke widths are on that 24-unit grid too, so they scale with the size.
struct FocusIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 16 * s, height: 16 * s))
        p.addEllipse(in: CGRect(x: 9.5 * s, y: 9.5 * s, width: 5 * s, height: 5 * s))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// `M9 6v12M15 6v12` (Icons.tsx PauseIcon).
struct PauseIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        for x in [9.0, 15.0] {
            p.move(to: CGPoint(x: x * s, y: 6 * s))
            p.addLine(to: CGPoint(x: x * s, y: 18 * s))
        }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

enum FinishStep {
    case idle, ticked, leaving
}

/// One card's finish animation: the step it's at, and how far it flies.
struct Finish: Equatable {
    var step: FinishStep
    var flight: CGSize = .zero
}

/// "Focus ◎": the text first, then the icon.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// The iPhone's card menu (long-press), with the same items as the Mac's
/// themed one: category first, then Open, Move, Focus, Mark done, Open in
/// Obsidian, Delete.
struct CardMenu: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.openURL) private var openURL
    let task: BoardTask

    var body: some View {
        Picker("Category", selection: Binding(get: { task.area }, set: { store.setCategory(task.id, to: $0) })) {
            ForEach(store.settings.categories) { c in
                Text(c.name).tag(c.id)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") { store.openID = task.id }
        if task.status == .today {
            Button("Move to Backlog", systemImage: "arrow.down") { store.moveToTop(task.id, of: .backlog) }
            Button(task.focus ? "Pause" : "Focus", systemImage: task.focus ? "pause" : "scope") { store.toggleFocus(task.id) }
        } else {
            Button("Move to Today", systemImage: "arrow.up") { store.moveToTop(task.id, of: .today) }
        }
        Button("Mark done", systemImage: "checkmark") { store.finish(task.id) }
        if let url = store.obsidianURL(task.id) {
            Button("Open in Obsidian", systemImage: "arrow.up.right") { openURL(url) }
        }
        Divider()
        Button("Delete file", systemImage: "trash", role: .destructive) { store.delete(task.id) }
    }
}

/// The title, cut off with "…" after a few lines, with the #private lock after it.
private struct TitleText: View {
    let task: BoardTask
    let size: CGFloat
    let weight: Font.Weight
    let lines: Int
    let theme: Theme
    var struck = false
    /// The full-title tooltip may show (not while dragging or finishing).
    var tips = false
    /// On the ink focus card the tooltip is light (.is-focus .opener::after).
    var inverted = false
    /// Debug screenshots (`-hover`): shown as if hovered.
    var debugHover = false

    /// Heights of the title as shown (clamped) and as it would be in full.
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        // Text pieces joined with `+` flow as one paragraph, so the lock sits
        // right after the last word, like the inline icon in the Tauri app.
        var text = Text(task.title)
        if task.isPrivate {
            text = text + Text("  ") + Text(Image(systemName: "lock")).font(.system(size: size * 0.62, weight: .semibold)).foregroundStyle(.secondary)
        }
        return styled(text)
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            // The same text with no line limit, unseen: if it's taller, the
            // title is cut off ("…") and the tooltip has something to show.
            .background(alignment: .top) {
                styled(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
        #if os(macOS)
            .onHover { h in
                // Shows after half a second of hovering, hides at once (as the CSS).
                withAnimation(h ? .easeOut(duration: 0.15).delay(0.5) : .easeOut(duration: 0.12)) { hovering = h }
            }
            .overlay(alignment: .bottom) {
                if tips && fullHeight > shownHeight + 1 {
                    fullTitle
                }
            }
        #endif
    }

    private func styled(_ text: Text) -> some View {
        text
            // The size is animated (17 → 24pt into focus): a plain font change
            // would jump, `GrowingFont` passes every size in between.
            .modifier(GrowingFont(size: size, weight: weight, theme: theme))
            .strikethrough(struck)
            .lineSpacing(1)
            .multilineTextAlignment(.leading)
    }

    /// `.opener[data-clipped]::after`: the whole title in a small ink label
    /// 6pt under the title, as wide as it.
    private var fullTitle: some View {
        Text(task.title)
            .font(theme.font(12, .medium))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(inverted ? theme.ink : theme.bg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(inverted ? theme.bg : theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.bottom) { d in d[.top] - 6 }
            .offset(y: hovering || debugHover ? 0 : -3)
            .opacity(hovering || debugHover ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A font whose size SwiftUI can animate. `Animatable` with `animatableData`
/// means: during an animation, call `body` again for every in-between value.
private struct GrowingFont: ViewModifier, @preconcurrency Animatable {
    var size: CGFloat
    let weight: Font.Weight
    let theme: Theme

    // `@preconcurrency Animatable` above: SwiftUI drives this from the main
    // thread, as views are, so Swift 6 can trust it without extra locks.
    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content
            .font(theme.font(size, weight))
            .tracking(Theme.tracking(-0.01, size: size))
    }
}

/// A category dot.
struct CategoryDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// The round check (.ring): a 1.5pt circle in the card's text colour.
/// Hover: a soft tint inside and a faint tick (40%) that draws itself, so
/// it's clear a click finishes the task. Finishing: it fills with the accent
/// and the tick draws in the accent's text colour.
struct CheckRing: View {
    var size: CGFloat = 22
    var step: FinishStep = .idle
    var hover = false
    let theme: Theme

    var body: some View {
        let ticked = step != .idle
        ZStack {
            Circle().fill(ticked ? theme.accent : (hover ? theme.hover : .clear))
            // `.foreground` = the card's text colour (ink, or the background on the focus card).
            Circle().strokeBorder(ticked ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.foreground), lineWidth: 1.5)
            Tick()
                .trim(from: 0, to: ticked || hover ? 1 : 0)
                .stroke(ticked ? AnyShapeStyle(theme.onAccent) : AnyShapeStyle(.foreground),
                        style: StrokeStyle(lineWidth: 3.2 * 13 / 24, lineCap: .round, lineJoin: .round))
                .opacity(ticked ? 1 : (hover ? 0.4 : 0))
                // Icons.tsx Tick: 13pt, stroke 3.2 on its 24-unit grid.
                .frame(width: 13, height: 13)
                // stroke-dashoffset 0.24s after 0.06s: the tick draws itself.
                .animation(.easeOut(duration: 0.24).delay(0.06), value: hover)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A tick mark: `M5 12.5l4.5 4.5L19 7.5` on a 24×24 grid.
struct Tick: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 5 * s, y: 12.5 * s))
        p.addLine(to: CGPoint(x: 9.5 * s, y: 17 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 7.5 * s))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Card measurements: roomy and compact from styles.css; minimal (one row) is
/// the SwiftUI app's own.
private struct Metrics {
    var padTop: CGFloat, padSide: CGFloat, padBottom: CGFloat
    var gap: CGFloat, minHeight: CGFloat
    var titleSize: CGFloat, titleWeight: Font.Weight, lines: Int
    var dotBox: CGFloat

    static func today(_ density: CardDensity) -> Metrics {
        switch density {
        case .roomy: Metrics(padTop: 16, padSide: 16, padBottom: 8, gap: 12, minHeight: 128, titleSize: 17, titleWeight: .medium, lines: 3, dotBox: 32)
        case .compact: Metrics(padTop: 10, padSide: 12, padBottom: 2, gap: 6, minHeight: 84, titleSize: 15, titleWeight: .medium, lines: 3, dotBox: 32)
        case .minimal: Metrics(padTop: 2, padSide: 12, padBottom: 2, gap: 0, minHeight: 42, titleSize: 14, titleWeight: .medium, lines: 1, dotBox: 28)
        }
    }

    static func focus(_ density: CardDensity) -> Metrics {
        var m = today(density)
        m.titleSize = [.roomy: 24, .compact: 19, .minimal: 16][density]!
        m.titleWeight = .semibold
        m.lines = density == .compact ? 2 : m.lines
        return m
    }

    static func backlog(_ density: CardDensity) -> Metrics {
        switch density {
        case .roomy: Metrics(padTop: 12, padSide: 12, padBottom: 4, gap: 10, minHeight: 88, titleSize: 14, titleWeight: .medium, lines: 3, dotBox: 28)
        case .compact: Metrics(padTop: 8, padSide: 10, padBottom: 0, gap: 4, minHeight: 60, titleSize: 13, titleWeight: .medium, lines: 2, dotBox: 28)
        case .minimal: Metrics(padTop: 0, padSide: 10, padBottom: 0, gap: 0, minHeight: 32, titleSize: 13, titleWeight: .medium, lines: 1, dotBox: 26)
        }
    }
}
