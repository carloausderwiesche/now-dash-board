// The cards. Today cards are big and tinted with their category colour;
// Backlog cards are smaller and plain, with only a colour dot (DESIGN.md).

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
        let cat = category(for: task.area, in: store.categories)
        let isToday = style == .today
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if isToday {
                    Ring(color: theme.ink.opacity(0.55))
                } else {
                    Circle().fill(cat.color.strong(in: theme)).frame(width: 10, height: 10).padding(.top, 5)
                }
                Text(task.title)
                    .font(theme.font(isToday ? 17 : 15, isToday ? .medium : .regular))
                    // Long titles stop with "…": 3 lines on Today, 2 on Backlog.
                    .lineLimit(isToday ? 3 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardFooter(task: task)
        }
        .padding(isToday ? 16 : 12)
        .frame(maxWidth: .infinity, minHeight: isToday ? 96 : 0, alignment: .topLeading)
        .background(isToday ? cat.color.tint(in: theme) : theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .overlay {
            if !isToday {
                RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.line, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(cat.name)
    }
}

/// The one card you're working on: black (the theme's ink), full width, NOW.
struct FocusCard: View {
    @Environment(BoardStore.self) private var store
    let task: BoardTask

    var body: some View {
        let theme = store.theme
        VStack(alignment: .leading, spacing: 10) {
            Text("NOW")
                .font(theme.font(11, .semibold))
                .tracking(1.2)
                .foregroundStyle(theme.bg.opacity(0.7))
            HStack(alignment: .top, spacing: 12) {
                Ring(color: theme.bg.opacity(0.7))
                Text(task.title)
                    .font(theme.font(22, .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardFooter(task: task, onDark: true)
        }
        .foregroundStyle(theme.bg)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus: \(task.title)")
    }
}

/// Small facts under the title: checklist progress and the #private lock.
struct CardFooter: View {
    @Environment(BoardStore.self) private var store
    let task: BoardTask
    var onDark = false

    var body: some View {
        let theme = store.theme
        let doneItems = task.items.filter(\.done).count
        if !task.items.isEmpty || task.isPrivate {
            HStack(spacing: 10) {
                if !task.items.isEmpty {
                    Label("\(doneItems)/\(task.items.count)", systemImage: "checklist")
                }
                if task.isPrivate {
                    Image(systemName: "lock.fill").accessibilityLabel("Private")
                }
            }
            .font(theme.font(12, .medium))
            .foregroundStyle(onDark ? theme.bg.opacity(0.7) : theme.muted)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// The round check. Not tappable yet: completing comes with editing.
struct Ring: View {
    let color: Color

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.5)
            .frame(width: 20, height: 20)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }
}
