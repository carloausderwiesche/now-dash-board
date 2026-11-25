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
        #if os(macOS)
            // No blue focus ring on whichever button happens to have keyboard
            // focus (the Tauri app only outlines things while you use the keyboard).
            .focusEffectDisabled()
            // The board runs up under the (hidden) title bar: .page's 48pt top
            // padding already leaves room for the window buttons.
            .ignoresSafeArea(edges: .top)
        #endif
        .background(theme.bg.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .animation(.easeOut(duration: 0.45), value: theme.id)
        .overlay(alignment: .bottom) { UndoPill() }
        .refreshable { await store.reload() }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reload() } }
        }
        #if os(macOS)
            // Mac: the panel slides in from the right, quick add drops in at the
            // top, both over a scrim (a soft shade over the board).
            .overlay { macOverlays }
        #else
            // iPhone: both are sheets from below.
            .sheet(isPresented: Binding(get: { store.openID != nil }, set: { if !$0 { store.openID = nil } })) {
                if let id = store.openID {
                    DetailPanel(id: id)
                        .presentationDetents([.large])
                        .presentationCornerRadius(store.theme.radiusLarge)
                }
            }
            .sheet(isPresented: Binding(get: { store.adding }, set: { store.adding = $0 })) {
                QuickAdd()
                    .presentationDetents([.height(150)])
                    .presentationCornerRadius(store.theme.radiusLarge)
                    .presentationBackground(store.theme.surface)
            }
        #endif
        // The system's folder picker (Files on iOS, Finder's panel on the Mac).
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await store.use(folder: url) }
            }
        }
    }
}

#if os(macOS)
    extension BoardView {
        /// The detail panel and quick add, over a scrim. Clicking the scrim closes them.
        @ViewBuilder
        var macOverlays: some View {
            let theme = store.theme
            ZStack {
                if store.openID != nil || store.adding {
                    theme.scrim
                        .ignoresSafeArea()
                        .onTapGesture {
                            store.openID = nil
                            store.adding = false
                        }
                        .transition(.opacity)
                }
                if let id = store.openID {
                    HStack {
                        Spacer(minLength: 0)
                        DetailPanel(id: id)
                            .id(id)
                            .frame(width: 460)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radiusLarge))
                            .overlay(RoundedRectangle(cornerRadius: theme.radiusLarge).strokeBorder(theme.line, lineWidth: 1))
                            .shadow(color: .black.opacity(0.45), radius: 35, y: 30)
                    }
                    .padding(12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if store.adding {
                    VStack {
                        QuickAdd()
                            .frame(width: 600)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radiusLarge))
                            .shadow(color: .black.opacity(0.45), radius: 40, y: 30)
                            .padding(.top, 150)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.3), value: store.openID)
            .animation(.easeOut(duration: 0.25), value: store.adding)
        }
    }
#endif

/// Everything inside the scroll view. Separate, so a snapshot can render it.
struct BoardContent: View {
    @Environment(BoardStore.self) private var store
    var narrow: Bool
    var pickFolder: () -> Void = {}

    var body: some View {
        let lists = store.lists
        // A card flying into Done must pass over the sections below its own.
        let flying = { (list: [BoardTask]) in list.contains { store.finishing[$0.id] != nil } ? 1.0 : 0 }
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
                .zIndex(flying(lists.today))
                CardSection(title: "Backlog", cards: lists.backlog, style: .backlog, narrow: narrow,
                            empty: ("Backlog is empty", "Ideas and later things go here"))
                    .zIndex(flying(lists.backlog))
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
        .coordinateSpace(name: boardSpace)
        // The bottom of what the scroll view shows, in board coordinates.
        .onGeometryChange(for: CGFloat.self) { $0.bounds(of: .scrollView)?.maxY ?? .infinity } action: { bottom in
            store.visibleBottom = bottom
        }
        // The copy of the card that follows the pointer while dragging.
        .overlay(alignment: .topLeading) {
            let drag = store.drag
            if let id = drag.id, let task = store.task(id) {
                CardView(task: task, style: task.status == .today ? .today : .backlog, mode: .clone)
                    .frame(width: drag.cloneSize.width, height: drag.cloneSize.height)
                    .offset(x: drag.cloneOrigin.x, y: drag.cloneOrigin.y)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }  // follows the pointer exactly
            }
        }
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
    @State private var hovering = false

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
                // .dotbtn:hover: ×1.4 with a small overshoot.
                .scaleEffect(hovering ? 1.4 : 1)
                .animation(.timingCurve(0.2, 1.8, 0.4, 1, duration: 0.3), value: hovering)
                // A 32pt target: the dots sit ~38pt apart, as in the Tauri app.
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(pressed: 0.8))
        .onHover { hovering = $0 }
        .tip(category.name)
        .cursor(.pointingHand)
        .accessibilityLabel("Highlight \(category.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings: theme, card size and the Tasks folder. A menu for now; the full
/// popover from the Tauri app (categories, vault) comes with editing.
struct SettingsMenu: View {
    @Environment(BoardStore.self) private var store
    var pickFolder: () -> Void
    @State private var hovering = false

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
            // .iconbtn: muted, ink on hover.
            SlidersIcon()
                .stroke(hovering ? store.theme.ink : store.theme.muted, style: StrokeStyle(lineWidth: 1.7 * 18 / 24, lineCap: .round, lineJoin: .round))
                .animation(.easeOut(duration: 0.2), value: hovering)
                .frame(width: 18, height: 18)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
        .accessibilityLabel("Settings")
    }
}

/// The round + button: opens quick add (also the N key on the Mac).
struct PlusButton: View {
    @Environment(BoardStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let theme = store.theme
        Button {
            store.adding = true
        } label: {
            ZStack {
                Circle().fill(theme.ink)
                PlusIcon()
                    .stroke(theme.bg, style: StrokeStyle(lineWidth: 2.2 * 20 / 24, lineCap: .round))
                    .frame(width: 20, height: 20)
                    // .plus:hover turns the + a quarter and grows it a little.
                    .rotationEffect(.degrees(hovering ? 90 : 0))
            }
            .frame(width: 48, height: 48)
            .scaleEffect(hovering ? 1.05 : 1)
            .contentShape(Circle())
        }
        // .plus:active shrinks to 0.9; hover turns the + a quarter and grows
        // it a little, with the CSS's overshoot (cubic-bezier(0.2, 1.6, 0.4, 1)).
        .buttonStyle(PressScale(pressed: 0.9))
        .keyboardShortcut("n", modifiers: [])
        .onHover { h in withAnimation(.timingCurve(0.2, 1.6, 0.4, 1, duration: 0.3)) { hovering = h } }
        .cursor(.pointingHand)
        .help("Add task  N")
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
    /// iPhone: the system drag is over this section.
    @State private var targeted = false

    var body: some View {
        let compact = store.settings.compact
        let drag = store.drag
        let (minWidth, gap): (CGFloat, CGFloat) =
            style == .today ? (compact ? 160 : 200, compact ? 8 : 12) : (compact ? 150 : 180, compact ? 6 : 10)
        // The list as drawn: while dragging, with the preview ("ghost") where
        // the card will land and the dragged card's slot closed if it moved.
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = drag.displayed(cards.map(\.id), status: status)
        let over = drag.id != nil && drag.target?.status == status
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: title, count: cards.count)
            if shown.isEmpty {
                EmptyBox(title: empty.0, hint: empty.1, small: style == .backlog)
            } else {
                CardGridLayout(minWidth: minWidth, spacing: gap) {
                    ForEach(shown, id: \.self) { id in
                        if id == DropRules.ghostID, let dragID = drag.id, let dragged = store.task(dragID) {
                            CardView(task: dragged, style: style, mode: .ghost)
                                .transition(.opacity.animation(.easeOut(duration: 0.3)))
                                .measure(id, span: spanOf(dragged), in: drag)
                                // Last: the grid reads the span from its direct child.
                                .gridSpan(spanOf(dragged))
                        } else if let task = byID[id] ?? store.task(id) {
                            card(task)
                                .measure(id, span: spanOf(task), in: drag)
                                // Last: the grid reads span and layering from its direct child.
                                .gridSpan(spanOf(task))
                                .zIndex(store.finishing[id] != nil ? 4 : store.hoveredID == id ? 3 : 0)
                        }
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { grid in
                    drag.zones[status, default: DropZone(status: status, frame: grid, grid: grid)].grid = grid
                    drag.gridColumns[status] = DropRules.columns(width: grid.width, minWidth: minWidth, spacing: gap)
                    drag.gridSpacing[status] = gap
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { frame in
            drag.zones[status, default: DropZone(status: status, frame: frame, grid: nil)].frame = frame
        }
        .onChange(of: shown.isEmpty) { _, empty in
            if empty { drag.zones[status]?.grid = nil }
        }
        .animation(.easeOut(duration: 0.3), value: store.filter)
        // .zone.over: the target section takes a soft tint that spills a little past its edges.
        .background {
            RoundedRectangle(cornerRadius: store.theme.radiusLarge)
                .fill(store.theme.hover)
                .padding(-14)
                .opacity(over || targeted ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: over || targeted)
        }
        #if os(iOS)
            // iPhone: the system drag (long-press a card). Dropping on the section: at the end.
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) { store.move(id, to: status) }
                return true
            } isTargeted: { targeted = $0 }
        #endif
    }

    private var status: TaskStatus { style == .today ? .today : .backlog }

    /// The focus card is twice as wide in Today (not on a phone).
    private func spanOf(_ task: BoardTask) -> Int {
        style == .today && task.focus && !narrow ? 2 : 1
    }

    /// A card with its drag gesture: the Mac's own drag (DragController), the
    /// iPhone's system drag.
    @ViewBuilder
    private func card(_ task: BoardTask) -> some View {
        #if os(macOS)
            CardView(task: task, style: style)
                // `simultaneousGesture` so the card's buttons still get their clicks:
                // the drag only starts after 5pt of movement.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .named(boardSpace))
                        .onChanged { v in
                            store.drag.moved(task.id, start: v.startLocation, location: v.location, status: status)
                        }
                        // The release (and Esc) is handled by DragController's
                        // event monitor, which outlives this card's view.
                )
        #else
            CardView(task: task, style: style)
                .draggable(task.id) {
                    CardView(task: task, style: style).frame(width: 180).environment(store)
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, id != task.id else { return false }
                    withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) {
                        store.move(id, to: status, before: task.id)
                    }
                    return true
                }
        #endif
    }
}

/// The coordinate space the drag measures everything in: the board's content.
let boardSpace = "board"

extension View {
    /// Tells the drag controller where this card is (and how wide it spans).
    func measure(_ id: String, span: Int, in drag: DragController) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { frame in
            drag.cardFrames[id] = frame
            drag.spans[id] = span
        }
        .onDisappear { drag.cardFrames[id] = nil }
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
                    Button { store.openID = t.id } label: {
                        Text(t.title).font(theme.font(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let from = t.from {
                        Text(from).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                    Button("Accept") { store.accept(t.id) }
                        .buttonStyle(.plain)
                        .font(theme.font(12, .medium))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                    Button("Dismiss") { store.delete(t.id) }
                        .buttonStyle(.plain)
                        .font(theme.font(12, .medium))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .help("Dismiss (deletes the file)")
                }
                .frame(minHeight: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                .opacity(store.deleting.contains(t.id) ? 0 : 1)
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
    /// The Done number's short nudge when a task arrives (.bump).
    @State private var bump = false
    /// iPhone: the system drag is over Done.
    @State private var targeted = false

    /// A card is being dragged over Done (either kind of drag): the number turns accent.
    private var over: Bool { targeted || (store.drag.id != nil && store.drag.target?.status == .done) }

    private var todayString: String { String(TaskFormat.timestamp(.now).prefix(10)) }

    /// "Mon 23" for a task finished on another day.
    private func dayLabel(_ stamp: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(stamp.prefix(10))) else { return "" }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }

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
                        .foregroundStyle(bump || over ? theme.accent : theme.ink)
                        .scaleEffect(bump ? 1.08 : 1, anchor: .bottomLeading)
                        // Where finished cards fly to.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { frame in
                            store.doneTarget = frame
                        }
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
            #if os(iOS)
                // Dropping a card on Done completes it.
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, store.task(id)?.status != .done else { return false }
                    store.finish(id)
                    return true
                } isTargeted: { targeted = $0 }
            #endif
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { frame in
                store.drag.zones[.done] = DropZone(status: .done, frame: frame, grid: nil)
            }
            .onChange(of: today.count) { old, new in
                guard new > old else { return }
                withAnimation(.easeOut(duration: 0.15)) { bump = true }
                withAnimation(.easeOut(duration: 0.35).delay(0.15)) { bump = false }
            }

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
                            if let done = t.done, !done.hasPrefix(todayString) {
                                Text(dayLabel(done)).font(theme.font(12)).foregroundStyle(theme.muted).padding(.horizontal, 8)
                            }
                            Button("Undo") { store.reopen(t.id) }
                                .buttonStyle(.plain)
                                .font(theme.font(12, .medium))
                                .padding(.horizontal, 8)
                                .frame(height: 32)
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

/// "Deleted “…” · Undo": a small ink pill at the bottom for a few seconds
/// after a delete (ADR 0010). ⌘Z does the same on the Mac.
struct UndoPill: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        let theme = store.theme
        ZStack {
            if let deleted = store.undoable {
                HStack(spacing: 16) {
                    Text("Deleted “\(deleted.task.title)”")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Undo") { store.undoDelete() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        .underline()
                        .keyboardShortcut("z", modifiers: .command)
                        .cursor(.pointingHand)
                }
                .font(theme.font(13, .medium))
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .frame(maxWidth: 420)
                .background(theme.ink, in: Capsule())
                .cssShadow(y: 14, blur: 34, spread: -14, opacity: 0.45, radius: 22)
                .padding(.bottom, 24)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
