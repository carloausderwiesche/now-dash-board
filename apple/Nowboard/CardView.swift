// The cards, measured from src/styles.css (.today-card, .backlog-card,
// .card-foot, .ring). Today cards are big and tinted with their category
// colour; the focus card is ink-coloured and twice as wide; Backlog cards are
// small and plain. Title on top; the category dot bottom-left and the round
// check bottom-right.

import NowboardKit
import SwiftUI

enum CardStyle {
    case today, backlog
}

struct CardView: View {
    @Environment(BoardStore.self) private var store
    let task: BoardTask
    let style: CardStyle

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

        VStack(alignment: .leading, spacing: m.gap) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                TitleText(task: task, size: m.titleSize, weight: m.titleWeight, lines: m.lines, theme: theme)
                if style == .today && !task.items.isEmpty {
                    Text("\(task.items.filter(\.done).count) / \(task.items.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            Spacer(minLength: 0)
            // .card-foot: dot, (NOW), spacer, ring.
            HStack(spacing: 2) {
                CategoryDot(color: cat.color.strong(in: theme), size: 10)
                    .frame(width: m.dotBox, height: m.dotBox)
                    .padding(.leading, style == .today ? -8 : -7)
                    .help(cat.name)
                    .accessibilityLabel(cat.name)
                if focus {
                    Text("NOW")
                        .font(theme.font(11, .semibold))
                        .tracking(Theme.tracking(0.14, size: 11))
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
                if style == .today {
                    CheckRing(size: 22)
                        .frame(width: 40, height: compact ? 34 : 40)
                        .padding(.trailing, -8)
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
        .accessibilityElement(children: .combine)
    }
}

/// The title, cut off with "…" after a few lines, with the #private lock after it.
private struct TitleText: View {
    let task: BoardTask
    let size: CGFloat
    let weight: Font.Weight
    let lines: Int
    let theme: Theme

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
/// Not tappable yet: completing comes with editing.
struct CheckRing: View {
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .strokeBorder(lineWidth: 1.5)
            .frame(width: size, height: size)
            .accessibilityLabel("Not done")
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
