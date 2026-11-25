// The Mac's card menu (DESIGN.md, "Right-click a card"; .card-menu in
// src/styles.css): drawn in the theme, like the Tauri app's, with the category
// dots on top. The iPhone keeps the system long-press menu (CardMenu in
// CardView.swift), which lifts the card and fits the phone better (ADR 0012).

#if os(macOS)
    import AppKit
    import NowboardKit
    import SwiftUI

    /// Catches right-clicks (and control-clicks) on cards. SwiftUI has no
    /// right-click gesture with a position, so this watches the window's mouse
    /// events, like DragController does for drags. While the menu is open the
    /// page holds still (scrolling is swallowed), as with a system menu.
    @MainActor
    final class CardMenuMonitor {
        static let shared = CardMenuMonitor()
        private var monitor: Any?

        func start(store: BoardStore) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .scrollWheel]) { [weak store] e in
                guard let store, let window = e.window, !(window is QuickPanel) else { return e }
                if e.type == .scrollWheel { return store.menu == nil ? e : nil }
                let rightClick = e.type == .rightMouseDown || e.modifierFlags.contains(.control)
                guard rightClick else { return e }
                // Only on a card, and only when nothing else is open on top of the board.
                guard store.openID == nil, !store.adding, !store.showingSettings, store.drag.id == nil,
                    let id = store.hoveredID, let task = store.task(id), task.status == .today || task.status == .backlog
                else {
                    store.menu = nil
                    return e
                }
                let height = window.contentView?.bounds.height ?? 0
                // AppKit counts y from the bottom, SwiftUI from the top.
                store.menu = (id, CGPoint(x: e.locationInWindow.x, y: height - e.locationInWindow.y))
                return nil
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak store] _ in
                MainActor.assumeIsolated { store?.menu = nil }
            }
        }
    }

    /// The menu layer: an invisible catch over the window (a click anywhere
    /// else closes the menu) and the menu at the pointer, flipped near edges.
    struct CardMenuLayer: View {
        @Environment(BoardStore.self) private var store
        @State private var size: CGSize?

        var body: some View {
            GeometryReader { window in
                if let menu = store.menu, let task = store.task(menu.id) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { store.menu = nil }
                    let place = placeMenu(at: menu.at, size: size ?? .zero, in: window.size)
                    CardMenuPopup(task: task)
                        .id(menu.id)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                        // Measured first, then placed, so it never shows half off-screen.
                        .opacity(size == nil ? 0 : 1)
                        .offset(x: place.x, y: place.y)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity))
                }
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.14), value: store.menu?.id)
            .onChange(of: store.menu?.id) { _, id in if id == nil { size = nil } }
        }
    }

    /// One row of the menu.
    private struct Item {
        let text: String
        var icon: MenuIcon?
        var danger = false
        var enabled = true
        let action: () -> Void
    }

    private enum MenuIcon {
        case up, down, focus, pause, done, external, trash
    }

    struct CardMenuPopup: View {
        @Environment(BoardStore.self) private var store
        @Environment(\.openURL) private var openURL
        let task: BoardTask
        /// The row under the pointer or picked with the arrow keys.
        @State private var highlighted: Int?
        @State private var hoverCategory: String?
        @FocusState private var focused: Bool

        var body: some View {
            let theme = store.theme
            let groups = groups()
            let rows = groups.flatMap { $0 }
            VStack(alignment: .leading, spacing: 0) {
                categories(theme: theme)
                ForEach(Array(groups.enumerated()), id: \.offset) { g, group in
                    Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
                    ForEach(Array(group.enumerated()), id: \.offset) { r, item in
                        let index = groups.prefix(g).reduce(0) { $0 + $1.count } + r
                        row(item, on: highlighted == index, theme: theme)
                            .onHover { inside in
                                if inside { highlighted = index } else if highlighted == index { highlighted = nil }
                            }
                    }
                }
            }
            .padding(6)
            .frame(width: 232)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusLarge).strokeBorder(theme.line, lineWidth: 1))
            .cssShadow(y: 18, blur: 40, spread: -18, opacity: 0.35, radius: theme.radiusLarge)
            .foregroundStyle(theme.ink)
            // Like a macOS menu: nothing is highlighted until you point or press an arrow key.
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.escape) {
                store.menu = nil
                return .handled
            }
            .onKeyPress(.downArrow) {
                highlighted = next(after: highlighted, in: rows, step: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlighted = next(after: highlighted, in: rows, step: -1)
                return .handled
            }
            .onKeyPress(.return) {
                if let i = highlighted, rows[i].enabled { run(rows[i]) }
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Card")
        }

        /// The next enabled row, wrapping around.
        private func next(after i: Int?, in rows: [Item], step: Int) -> Int? {
            var j = i ?? (step > 0 ? -1 : rows.count)
            for _ in rows.indices {
                j = (j + step + rows.count) % rows.count
                if rows[j].enabled { return j }
            }
            return nil
        }

        private func run(_ item: Item) {
            store.menu = nil
            item.action()
        }

        /// What the menu offers, in groups with a line between them (cardMenu.ts).
        private func groups() -> [[Item]] {
            let id = task.id
            let today = task.status == .today
            var first = [Item(text: "Open") { store.openID = id }]
            first.append(
                today
                    ? Item(text: "Move to Backlog", icon: .down) { store.moveToTop(id, of: .backlog) }
                    : Item(text: "Move to Today", icon: .up) { store.moveToTop(id, of: .today) })
            if today {
                first.append(
                    task.focus
                        ? Item(text: "Stop focusing", icon: .pause) { store.toggleFocus(id) }
                        : Item(text: "Focus on this now", icon: .focus) { store.toggleFocus(id) })
            }
            first.append(Item(text: "Mark done", icon: .done) { store.finish(id) })
            let url = store.obsidianURL(id)
            return [
                first,
                [Item(text: "Open in Obsidian", icon: .external, enabled: url != nil) { if let url { openURL(url) } }],
                // No second click: Undo brings it back (ADR 0010).
                [Item(text: "Delete file", icon: .trash, danger: true) { store.delete(id) }],
            ]
        }

        /// .menu-cats: the category dots, the current one ringed, the name of
        /// the hovered (or current) one on the right.
        private func categories(theme: Theme) -> some View {
            let cats = store.settings.categories
            let current = category(for: task.area, in: cats)
            let shown = cats.first { $0.id == hoverCategory } ?? current
            return HStack(spacing: 0) {
                ForEach(cats) { c in
                    let color = c.color.strong(in: theme)
                    Button {
                        store.menu = nil
                        store.setCategory(task.id, to: c.id)
                    } label: {
                        Circle().fill(color).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(color, lineWidth: 1.5).padding(-4.5).opacity(c.id == current.id ? 1 : 0))
                            .scaleEffect(hoverCategory == c.id ? 1.18 : 1)
                            .animation(.easeOut(duration: 0.15), value: hoverCategory)
                            .frame(width: 26, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pointer)
                    .onHover { inside in
                        if inside { hoverCategory = c.id } else if hoverCategory == c.id { hoverCategory = nil }
                    }
                    .accessibilityLabel(c.name)
                    .accessibilityAddTraits(c.id == current.id ? .isSelected : [])
                }
                Spacer(minLength: 8)
                Text(shown.name)
                    .font(theme.font(12))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .padding(.trailing, 6)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
        }

        /// .menu-row: the text, the icon on the right (muted until highlighted).
        /// Delete is muted and turns accent when highlighted.
        private func row(_ item: Item, on: Bool, theme: Theme) -> some View {
            let lit = on && item.enabled
            let text: Color = item.danger ? (lit ? theme.accent : theme.muted) : theme.ink
            return Button {
                run(item)
            } label: {
                HStack {
                    Text(item.text).font(theme.font(13))
                    Spacer(minLength: 8)
                    if let icon = item.icon {
                        iconView(icon)
                            .foregroundStyle(item.danger ? text : (lit ? theme.ink : theme.muted))
                            .frame(width: 16)
                    }
                }
                .foregroundStyle(text)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(lit ? theme.well : .clear, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                .contentShape(Rectangle())
                .opacity(item.enabled ? 1 : 0.45)
            }
            .buttonStyle(.pointer)
            .disabled(!item.enabled)
            .help(item.enabled ? "" : "Demo board: choose a Tasks folder in Settings first")
        }

        @ViewBuilder
        private func iconView(_ icon: MenuIcon) -> some View {
            let style = { (w: CGFloat) in StrokeStyle(lineWidth: w * 14 / 24, lineCap: .round, lineJoin: .round) }
            switch icon {
            case .up: ArrowIcon(up: true).stroke(style: style(2.2)).frame(width: 14, height: 14)
            case .down: ArrowIcon(up: false).stroke(style: style(2.2)).frame(width: 14, height: 14)
            case .focus: FocusIcon().stroke(style: style(2.2)).frame(width: 12, height: 12)
            case .pause: PauseIcon().stroke(style: style(2.6)).frame(width: 12, height: 12)
            case .done: Tick().stroke(style: style(2.6)).frame(width: 14, height: 14)
            case .external: ExternalIcon().stroke(style: style(2.2)).frame(width: 14, height: 14)
            case .trash: TrashIcon().stroke(style: style(1.8)).frame(width: 14, height: 14)
            }
        }
    }
#endif
