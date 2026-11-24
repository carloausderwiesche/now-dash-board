// The board: one column, top to bottom (DESIGN.md, principle 3). Sizes and
// spacing come from src/styles.css (.page, .header, .section, .done-head…),
// so both apps look the same. Read-only for now: editing, completing and
// quick add are the next milestone.

import NowboardKit
import SwiftUI

struct BoardView: View {
    @Environment(BoardStore.self) private var store
    /// Coming back to the front reloads, so edits made elsewhere show up.
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickingFolder = false

    var body: some View {
        let theme = store.theme
        // GeometryReader tells us the window's width, for the narrow layout
        // (the CSS `@media (max-width: 640px)` rules: phones).
        GeometryReader { geo in
            ScrollView {
                BoardContent(narrow: geo.size.width < 640, pickFolder: { pickingFolder = true })
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.bg.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .animation(.easeOut(duration: 0.45), value: theme.id)
        .refreshable { await store.reload() }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reload() } }
        }
        // The system's folder picker (Files on iOS, Finder's panel on the Mac).
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await store.use(folder: url) }
            }
        }
    }
}

/// Everything inside the scroll view. Separate, so a snapshot can render it.
struct BoardContent: View {
    @Environment(BoardStore.self) private var store
    var narrow: Bool
    var pickFolder: () -> Void = {}

    var body: some View {
        let lists = store.lists
        // .page: gap 28 between the header and the column of sections.
        VStack(alignment: .leading, spacing: 28) {
            HeaderView(narrow: narrow, pickFolder: pickFolder)
            if let error = store.error {
                ErrorBar(message: error)
            }
            // .column: gap 48 between sections.
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 28) {
                    CardSection(title: "Today", cards: lists.today, style: .today, narrow: narrow,
                                empty: ("Nothing planned for today", "Drag a card up from Backlog, or press +"))
                    if !lists.suggested.isEmpty {
                        SuggestedStrip(tasks: lists.suggested)
                    }
                }
                CardSection(title: "Backlog", cards: lists.backlog, style: .backlog, narrow: narrow,
                            empty: ("Backlog is empty", "Ideas and later things go here"))
                DoneSection(today: lists.doneToday, recent: lists.doneRecent)
            }
        }
        // .page padding: 48 on the Mac (top 48 leaves room for the window
        // buttons, since there's no title bar), 20/16 on a phone.
        .padding(.top, narrow ? 20 : 48)
        .padding(.horizontal, narrow ? 16 : 48)
        .padding(.bottom, narrow ? 40 : 48)
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Header

/// Big day number with weekday and month beside it; on the right the
/// category dots (tap to highlight one), settings and the + button.
struct HeaderView: View {
    @Environment(BoardStore.self) private var store
    var narrow: Bool
    var pickFolder: () -> Void

    var body: some View {
        // CSS `.header { flex-wrap: wrap }`: date and tools on one line when
        // they fit (Mac), otherwise the tools wrap under the date, on the right
        // (phone). `ViewThatFits` uses the first layout that fits the width.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 40) {
                date
                Spacer(minLength: 0)
                tools
            }
            VStack(alignment: .trailing, spacing: 20) {
                date.frame(maxWidth: .infinity, alignment: .leading)
                tools
            }
        }
    }

    /// The big day number with weekday and month beside it.
    private var date: some View {
        let theme = store.theme
        let daySize: CGFloat = narrow ? 64 : 96
        return HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text(Date.now, format: .dateTime.day())
                .font(theme.font(daySize, .semibold))
                .tracking(Theme.tracking(-0.05, size: daySize))
                .monospacedDigit()
                .lineLimit(1)
                // CSS `line-height: 0.8`: no empty space above or below the digits.
                .padding(.vertical, theme.lineBoxTrim(daySize, lineHeight: 0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide)).fontWeight(.semibold)
                Text(Date.now, format: .dateTime.month(.wide)).foregroundStyle(theme.muted)
            }
            .font(theme.font(15))
            .lineLimit(1)
            // Sit a little above the number's baseline, like `padding-bottom: 2px` there.
            .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] - 1 }
        }
        // Never squeeze the date: it keeps its natural width, the layout wraps instead.
        .fixedSize()
    }

    /// Category dots, a divider, settings and the + button.
    private var tools: some View {
        HStack(spacing: 6) {
            ForEach(store.settings.categories) { c in
                FilterDot(category: c)
            }
            Rectangle().fill(store.theme.line).frame(width: 1, height: 20).padding(.horizontal, 8)
            SettingsMenu(pickFolder: pickFolder)
            PlusButton()
                .padding(.leading, 4)
        }
        .fixedSize()
    }
}

/// A header dot. Tapping highlights that category: other cards fade (DESIGN.md).
struct FilterDot: View {
    @Environment(BoardStore.self) private var store
    let category: Category

    var body: some View {
        let theme = store.theme
        let on = store.filter == category.id
        let color = category.color.strong(in: theme)
        Button {
            store.filter = on ? nil : category.id
        } label: {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .opacity(store.filter != nil && !on ? 0.35 : 1)
                // The ring around the selected dot: 1.5pt, 3pt away from it.
                .overlay(Circle().strokeBorder(color, lineWidth: 1.5).padding(-4.5).opacity(on ? 1 : 0))
                // A 32pt target: the dots sit ~38pt apart, as in the Tauri app.
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(category.name)
        .accessibilityLabel("Highlight \(category.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings: theme, card size and the Tasks folder. A menu for now; the full
/// popover from the Tauri app (categories, vault) comes with editing.
struct SettingsMenu: View {
    @Environment(BoardStore.self) private var store
    var pickFolder: () -> Void

    var body: some View {
        // `@Bindable` lets a view write to an @Observable object's property
        // through a binding (`$store.settings.theme`), here for the pickers.
        @Bindable var store = store
        Menu {
            Picker("Theme", selection: $store.settings.theme) {
                ForEach(["Rams", "Ive", "Pastel", "Eames"], id: \.self) { group in
                    Section(group) {
                        ForEach(Theme.all.filter { $0.group == group }) { t in
                            Text(t.name).tag(t.id)
                        }
                    }
                }
            }
            Picker("Cards", selection: $store.settings.compact) {
                Text("Roomy").tag(false)
                Text("Compact").tag(true)
            }
            Divider()
            Button("Choose Tasks folder…", action: pickFolder)
            if case .folder(let url) = store.source {
                Text("Reading \(url.lastPathComponent)")
                Button("Show the demo board") { Task { await store.useDemo() } }
            }
        } label: {
            SlidersIcon()
                .stroke(store.theme.muted, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Settings")
    }
}

/// The round + button. Quick add arrives with editing (next milestone).
struct PlusButton: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        let theme = store.theme
        ZStack {
            Circle().fill(theme.ink)
            PlusIcon()
                .stroke(theme.bg, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 20, height: 20)
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel("Add task")
    }
}

// MARK: - Sections

/// Today or Backlog: the heading with its count, then the cards.
struct CardSection: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let cards: [BoardTask]
    let style: CardStyle
    let narrow: Bool
    let empty: (String, String)

    var body: some View {
        let compact = store.settings.compact
        let (minWidth, gap): (CGFloat, CGFloat) =
            style == .today ? (compact ? 160 : 200, compact ? 8 : 12) : (compact ? 150 : 180, compact ? 6 : 10)
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: title, count: cards.count)
            if cards.isEmpty {
                EmptyBox(title: empty.0, hint: empty.1, small: style == .backlog)
            } else {
                CardGridLayout(minWidth: minWidth, spacing: gap) {
                    ForEach(cards, id: \.id) { task in
                        CardView(task: task, style: style)
                            // The focus card is twice as wide (not on a phone).
                            .gridSpan(style == .today && task.focus && !narrow ? 2 : 1)
                            // Highlighting a category fades the others to 22%.
                            .opacity(store.filter.map { $0 == task.area ? 1 : 0.22 } ?? 1)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: store.filter)
    }
}

/// .section-head: 22pt semibold title, the count in muted, a 2pt rule under it.
struct SectionHeading: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let count: Int

    var body: some View {
        let theme = store.theme
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                Text("\(count)").foregroundStyle(theme.muted).monospacedDigit()
            }
            .font(theme.font(22, .semibold))
            .tracking(Theme.tracking(-0.02, size: 22))
            Rectangle().fill(theme.ink).frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// .empty: a dashed box, centred text, saying what's missing and how to fill it.
struct EmptyBox: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let hint: String
    var small = false

    var body: some View {
        let theme = store.theme
        VStack(spacing: 4) {
            Text(title).font(theme.font(15, .semibold)).foregroundStyle(theme.ink)
            Text(hint).font(theme.font(13))
        }
        .foregroundStyle(theme.muted)
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: small ? (store.settings.compact ? 60 : 88) : 128)
        .overlay(
            RoundedRectangle(cornerRadius: small ? theme.radiusSmall : theme.radiusLarge)
                .strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

/// .suggested: a small strip under Today, not a section of its own.
struct SuggestedStrip: View {
    @Environment(BoardStore.self) private var store
    let tasks: [BoardTask]

    var body: some View {
        let theme = store.theme
        VStack(alignment: .leading, spacing: 0) {
            Text("SUGGESTED")
                .font(theme.font(11, .semibold))
                .tracking(Theme.tracking(0.14, size: 11))
                .foregroundStyle(theme.muted)
                .padding(.bottom, 6)
            ForEach(tasks, id: \.id) { t in
                HStack(spacing: 10) {
                    CategoryDot(color: category(for: t.area, in: store.settings.categories).color.strong(in: theme), size: 8)
                    Text(t.title).font(theme.font(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if let from = t.from {
                        Text(from).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                }
                .frame(minHeight: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
            }
        }
    }
}

/// .done-head: a 2pt rule above, the big number, "Done today" and the last
/// one finished. Tap to see the last 7 days.
struct DoneSection: View {
    @Environment(BoardStore.self) private var store
    let today: [BoardTask]
    let recent: [BoardTask]
    @State private var open = false

    var body: some View {
        let theme = store.theme
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(alignment: .bottom, spacing: 16) {
                    Text("\(today.count)")
                        .font(theme.font(56, .semibold))
                        .tracking(Theme.tracking(-0.04, size: 56))
                        .monospacedDigit()
                        .padding(.vertical, theme.lineBoxTrim(56, lineHeight: 0.85))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Done today").fontWeight(.semibold)
                        Text(today.first.map { "Last: \($0.title)" } ?? "Nothing finished yet today")
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    .font(theme.font(13))
                    .padding(.bottom, 2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .padding(.bottom, 4)
                }
                .padding(.top, 14)
                .padding(.bottom, 6)
                .overlay(alignment: .top) { Rectangle().fill(theme.ink).frame(height: 2) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the list" : "Shows the last 7 days")

            if open {
                VStack(spacing: 0) {
                    if recent.isEmpty {
                        Text("Nothing finished in the last 7 days")
                            .font(theme.font(13)).foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.leading, 8)
                    }
                    ForEach(recent, id: \.id) { t in
                        HStack(spacing: 12) {
                            CategoryDot(color: category(for: t.area, in: store.settings.categories).color.strong(in: theme))
                                .padding(.leading, 11)
                            Text(t.title).font(theme.font(14)).strikethrough().foregroundStyle(theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 40)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct ErrorBar: View {
    @Environment(BoardStore.self) private var store
    let message: String

    var body: some View {
        let theme = store.theme
        Text(message)
            .font(theme.font(13, .medium))
            .foregroundStyle(theme.onAccent)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
    }
}

// MARK: - Icons (the same drawings as src/components/Icons.tsx, on a 24×24 grid)

/// Two sliders: `M4 7h10M18 7h2M4 17h4M12 17h8` and circles at (16,7), (10,17), r 2.
struct SlidersIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        for (x1, x2, y) in [(4.0, 14.0, 7.0), (18, 20, 7), (4, 8, 17), (12, 20, 17)] {
            p.move(to: CGPoint(x: x1 * s, y: y * s))
            p.addLine(to: CGPoint(x: x2 * s, y: y * s))
        }
        p.addEllipse(in: CGRect(x: 14 * s, y: 5 * s, width: 4 * s, height: 4 * s))
        p.addEllipse(in: CGRect(x: 8 * s, y: 15 * s, width: 4 * s, height: 4 * s))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A plus: `M12 5v14M5 12h14`.
struct PlusIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        p.move(to: CGPoint(x: 5 * s, y: 12 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
