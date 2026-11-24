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

struct CardView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.openURL) private var openURL
    let task: BoardTask
    let style: CardStyle

    /// The pointer is over the card (Mac): shows the Focus / Today buttons and lifts it.
    @State private var hovering = false
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
        let lifted = hovering || store.openID == task.id

        VStack(alignment: .leading, spacing: m.gap) {
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
            .accessibilityLabel(task.title)
            .accessibilityHint("Opens the task")

            Spacer(minLength: 0)
            // .card-foot: dot, (NOW), spacer, Focus / Today ↑, ring.
            HStack(spacing: 2) {
                Button {
                    store.cycleCategory(task.id)
                } label: {
                    CategoryDot(color: cat.color.strong(in: theme), size: 10)
                        .frame(width: m.dotBox, height: m.dotBox)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, style == .today ? -8 : -7)
                .help("\(cat.name): click to change category")
                .accessibilityLabel("\(cat.name), change category")
                if focus {
                    Text("NOW")
                        .font(theme.font(11, .semibold))
                        .tracking(Theme.tracking(0.14, size: 11))
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
                revealButton(theme: theme)
                    .opacity(showReveal ? 1 : 0)
                    .animation(.easeOut(duration: 0.15).delay(showReveal ? 0.12 : 0), value: showReveal)
                if style == .today {
                    Button(action: finish) {
                        CheckRing(size: 22, step: finishing, accent: theme.accent, onAccent: theme.onAccent)
                            .frame(width: 40, height: compact ? 34 : 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -8)
                    .accessibilityLabel("Mark done")
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.top, m.padTop)
        .padding(.horizontal, m.padSide)
        .padding(.bottom, m.padBottom)
        .frame(maxWidth: .infinity, minHeight: m.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: style == .today ? theme.radiusCard : theme.radiusSmall)
            switch (style, focus) {
            case (.today, true):
                shape.fill(theme.ink).shadow(color: .black.opacity(0.55), radius: 17, y: 14)
            case (.today, false):
                shape.fill(cat.color.tint(in: theme))
            case (.backlog, _):
                shape.fill(theme.surface).overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            }
        }
        // .card:hover: lifts 3pt with a soft shadow.
        .shadow(color: .black.opacity(lifted && !focus ? 0.18 : 0), radius: 15, y: 14)
        .offset(y: lifted ? -3 : 0)
        // Finishing: shrink and fade away (the list then closes the gap).
        .scaleEffect(finishing == .leaving ? 0.6 : 1)
        .opacity(finishing == .leaving ? 0 : 1)
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.25), value: lifted)
        .onHover { hovering = $0 }
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

    /// The hover-only buttons always show on a phone, like the CSS's narrow rule.
    private var showReveal: Bool {
        #if os(iOS)
            return finishing == .idle
        #else
            return hovering && finishing == .idle
        #endif
    }

    @ViewBuilder
    private func revealButton(theme: Theme) -> some View {
        switch style {
        case .today:
            Button {
                store.toggleFocus(task.id)
            } label: {
                Label(task.focus ? "Pause" : "Focus", systemImage: task.focus ? "pause" : "scope")
                    .labelStyle(TrailingIcon())
                    .font(theme.font(12, .medium))
                    .frame(height: 32)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .help(task.focus ? "Stop focusing on this" : "Focus on this now")
        case .backlog:
            Button {
                store.moveToTop(task.id, of: .today)
            } label: {
                Text("Today ↑")
                    .font(theme.font(12, .medium))
                    .frame(height: 28)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
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

/// The round check (.ring): a 1.5pt circle in the card's text colour. When
/// finishing it fills with the accent and a tick draws itself.
struct CheckRing: View {
    var size: CGFloat = 22
    var step: FinishStep = .idle
    var accent: Color = .accentColor
    var onAccent: Color = .white

    var body: some View {
        let ticked = step != .idle
        ZStack {
            Circle().fill(ticked ? accent : .clear)
            // `.foreground` = the card's text colour (ink, or the background on the focus card).
            Circle().strokeBorder(ticked ? AnyShapeStyle(accent) : AnyShapeStyle(.foreground), lineWidth: 1.5)
            Tick()
                .trim(from: 0, to: ticked ? 1 : 0)
                .stroke(onAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
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
