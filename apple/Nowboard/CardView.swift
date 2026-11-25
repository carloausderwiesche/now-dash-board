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
    /// The finishing animation, step by step (see `finish()`).
    @State private var finishing: FinishStep = .idle
    @State private var confirmingDelete = false

    var body: some View {
        let theme = store.theme
        let cat = category(for: task.area, in: store.settings.categories)
        let focus = style == .today && task.focus
        let compact = store.settings.compact
        // `switch` as an expression picks the measurements for this kind of card.
        let m: Metrics =
            switch (style, focus) {
            case (.backlog, _): .backlog(compact: compact)
            case (.today, true): .focus(compact: compact)
            case (.today, false): .today(compact: compact)
            }
        let ink = focus ? theme.bg : theme.ink
        let dragging = store.drag.id != nil
        let isHovered = hovering || debugHover
        let isOverRing = overRing || (debugHover && debugRing)
        // .card:hover and .card.open lift the card 3pt; never while dragging.
        let lifted = mode == .normal && !dragging && finishing == .idle && (isHovered || store.openID == task.id)
        let shape = RoundedRectangle(cornerRadius: style == .today ? theme.radiusCard : theme.radiusSmall)

        VStack(alignment: .leading, spacing: m.gap) {
            title(m, compact: compact, theme: theme)
            Spacer(minLength: 0)
            footer(m, cat: cat, focus: focus, compact: compact, theme: theme,
                   reveal: showReveal(hovering: isHovered, overRing: isOverRing), overRing: isOverRing)
        }
        .foregroundStyle(ink)
        .padding(.top, m.padTop)
        .padding(.horizontal, m.padSide)
        .padding(.bottom, m.padBottom)
        .frame(maxWidth: .infinity, minHeight: m.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background {
            switch (style, focus) {
            case (.today, true): shape.fill(theme.ink)
            case (.today, false): shape.fill(cat.color.tint(in: theme))
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
        .offset(y: lifted ? -3 : 0)
        // Finishing: shrink and fade away (the list then closes the gap).
        .scaleEffect(finishing == .leaving ? 0.6 : 1)
        .opacity(opacity(dragging: dragging))
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.25), value: lifted)
        // Hover is read on an outer frame that doesn't move with the 3pt lift,
        // so pointing at the bottom edge can't lift and drop it in a loop
        // (the CSS uses an invisible strip for the same reason).
        .background(Color.clear.contentShape(Rectangle()).onHover { hovering = $0 })
        .cursor(.openHand)
        .zIndex(isHovered ? 3 : 0)
        .allowsHitTesting(mode == .normal)
        .contextMenu { CardMenu(task: task, confirmingDelete: $confirmingDelete) }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmingDelete) {
            Button("Delete file", role: .destructive) { store.delete(task.id) }
        } message: {
            Text("The task's .md file is deleted for good.")
        }
        // A small tap on the phone when a task is finished.
        .sensoryFeedback(.success, trigger: finishing == .done)
        .accessibilityElement(children: .contain)
    }

    /// The title (opens the panel) and the checklist count under it.
    private func title(_ m: Metrics, compact: Bool, theme: Theme) -> some View {
        Button {
            store.openID = task.id
        } label: {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                TitleText(task: task, size: m.titleSize, weight: m.titleWeight, lines: m.lines, theme: theme,
                          struck: finishing != .idle)
                if style == .today && !task.items.isEmpty {
                    Text("\(task.items.filter(\.done).count) / \(task.items.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .accessibilityLabel(task.title)
        .accessibilityHint("Opens the task")
    }

    /// .card-foot: the dot, (NOW), a spacer, Focus / Today ↑, the ring.
    private func footer(_ m: Metrics, cat: Category, focus: Bool, compact: Bool, theme: Theme, reveal: Bool, overRing isOverRing: Bool) -> some View {
        HStack(spacing: 2) {
            DotButton(color: cat.color.strong(in: theme), name: cat.name, box: m.dotBox, inverted: focus) {
                store.cycleCategory(task.id)
            }
            .padding(.leading, style == .today ? -8 : -7)
            if focus {
                Text("NOW")
                    .font(theme.font(11, .semibold))
                    .tracking(Theme.tracking(0.14, size: 11))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            revealButton(theme: theme)
                .opacity(reveal ? 1 : 0)
                // Shows after 0.12s (so passing through doesn't flash it), hides at once.
                .animation(.easeOut(duration: 0.15).delay(reveal ? 0.12 : 0), value: reveal)
                .allowsHitTesting(reveal)
            if style == .today {
                Button(action: finish) {
                    CheckRing(size: 22, step: finishing, hover: isOverRing, theme: theme)
                        .frame(width: 40, height: compact ? 34 : 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(.easeOut(duration: 0.2)) { overRing = h } }
                .cursor(.pointingHand)
                .padding(.trailing, -8)
                .accessibilityLabel("Mark done")
            }
        }
    }

    private func opacity(dragging: Bool) -> Double {
        if finishing == .leaving { return 0 }
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

    /// Ring fills with the accent and the tick draws itself, the title is
    /// struck through, then the card shrinks away and the task moves to Done.
    /// About 900ms in total (DESIGN.md: every completion under a second).
    private func finish() {
        guard finishing == .idle else { return }
        withAnimation(.easeOut(duration: 0.25)) { finishing = .ticked }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.35)) { finishing = .leaving }
            try? await Task.sleep(for: .milliseconds(380))
            finishing = .done
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) { store.complete(task.id) }
        }
    }
}

/// A category dot you can click (.dotbtn): grows ×1.4 on hover with a little
/// overshoot, shrinks to ×0.8 while pressed, and shows the category's name
/// in a tooltip right away.
struct DotButton: View {
    let color: Color
    let name: String
    var box: CGFloat = 32
    var size: CGFloat = 10
    var inverted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle().fill(color).frame(width: size, height: size)
                .scaleEffect(hovering ? 1.4 : 1)
                // cubic-bezier(0.2, 1.8, 0.4, 1) over 0.3s: a quick grow with a small overshoot.
                .animation(.timingCurve(0.2, 1.8, 0.4, 1, duration: 0.3), value: hovering)
                .frame(width: box, height: box)
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
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
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
    case idle, ticked, leaving, done
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

/// The card menu (right-click or long-press), like the Tauri app's: category
/// first, then Open, Move, Focus, Mark done, Open in Obsidian, Delete.
struct CardMenu: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.openURL) private var openURL
    let task: BoardTask
    @Binding var confirmingDelete: Bool

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
        Button("Mark done", systemImage: "checkmark") { store.complete(task.id) }
        if let url = store.obsidianURL(task.id) {
            Button("Open in Obsidian", systemImage: "arrow.up.right") { openURL(url) }
        }
        Divider()
        Button("Delete file", systemImage: "trash", role: .destructive) { confirmingDelete = true }
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

    var body: some View {
        // Text pieces joined with `+` flow as one paragraph, so the lock sits
        // right after the last word, like the inline icon in the Tauri app.
        var text = Text(task.title)
        if task.isPrivate {
            text = text + Text("  ") + Text(Image(systemName: "lock")).font(.system(size: size * 0.62, weight: .semibold)).foregroundStyle(.secondary)
        }
        return
            text
            .font(theme.font(size, weight))
            .tracking(Theme.tracking(-0.01, size: size))
            .strikethrough(struck)
            .lineSpacing(1)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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

/// Card measurements from styles.css, roomy and compact.
private struct Metrics {
    var padTop: CGFloat, padSide: CGFloat, padBottom: CGFloat
    var gap: CGFloat, minHeight: CGFloat
    var titleSize: CGFloat, titleWeight: Font.Weight, lines: Int
    var dotBox: CGFloat

    static func today(compact: Bool) -> Metrics {
        compact
            ? Metrics(padTop: 10, padSide: 12, padBottom: 2, gap: 6, minHeight: 84, titleSize: 15, titleWeight: .medium, lines: 3, dotBox: 32)
            : Metrics(padTop: 16, padSide: 16, padBottom: 8, gap: 12, minHeight: 128, titleSize: 17, titleWeight: .medium, lines: 3, dotBox: 32)
    }

    static func focus(compact: Bool) -> Metrics {
        var m = today(compact: compact)
        m.titleSize = compact ? 19 : 24
        m.titleWeight = .semibold
        m.lines = 2
        return m
    }

    static func backlog(compact: Bool) -> Metrics {
        compact
            ? Metrics(padTop: 8, padSide: 10, padBottom: 0, gap: 4, minHeight: 60, titleSize: 13, titleWeight: .medium, lines: 2, dotBox: 28)
            : Metrics(padTop: 12, padSide: 12, padBottom: 4, gap: 10, minHeight: 88, titleSize: 14, titleWeight: .medium, lines: 2, dotBox: 28)
    }
}
