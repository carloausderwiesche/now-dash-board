// The board: one column, top to bottom. Header → Today → Suggested →
// Backlog → Done (DESIGN.md, principle 3). Read-only for now: editing,
// drag and drop and quick add are the next milestones.

import NowboardKit
import SwiftUI

struct BoardView: View {
    @Environment(BoardStore.self) private var store
    /// Whether the app is in front. Coming back to the front reloads, so
    /// changes made elsewhere (Obsidian, the Mac) show up.
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickingFolder = false

    var body: some View {
        let theme = store.theme
        let lists = store.lists
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HeaderView(pickFolder: { pickingFolder = true })
                if let error = store.error {
                    ErrorBar(message: error)
                }
                TodaySection(focus: lists.focus, cards: lists.today)
                if !lists.suggested.isEmpty {
                    CardSection(title: "Suggested", cards: lists.suggested, style: .backlog, empty: nil)
                }
                CardSection(title: "Backlog", cards: lists.backlog, style: .backlog,
                            empty: ("Backlog is empty", "Anything you'll do later goes here."))
                DoneSummary(done: lists.doneToday)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg)
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .refreshable { await store.reload() }
        .task { await store.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reload() } }
        }
        // The system's folder picker. On iOS it shows the Files app's places:
        // On My iPhone, iCloud Drive, and other apps' folders.
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await store.use(folder: url) }
            }
        }
    }
}

// MARK: - Header

/// Big day number, weekday and month beside it; category dots and settings
/// on the right. Nothing else.
struct HeaderView: View {
    @Environment(BoardStore.self) private var store
    var pickFolder: () -> Void

    var body: some View {
        let theme = store.theme
        HStack(alignment: .center, spacing: 14) {
            Text(Date.now, format: .dateTime.day())
                .font(theme.font(96, .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(theme.font(17, .semibold))
                Text(Date.now, format: .dateTime.month(.wide))
                    .font(theme.font(17))
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ForEach(store.categories) { c in
                    Circle()
                        .fill(c.color.strong(in: theme))
                        .frame(width: 12, height: 12)
                        .help(c.name)
                        .accessibilityLabel(c.name)
                }
            }
            SettingsMenu(pickFolder: pickFolder)
        }
    }
}

/// Theme and Tasks folder. A menu for now; the full settings popover
/// (categories, compact cards) comes with editing.
struct SettingsMenu: View {
    @Environment(BoardStore.self) private var store
    var pickFolder: () -> Void

    var body: some View {
        // `@Bindable` lets a view write to an @Observable object's property
        // through a binding (`$store.themeID`), here for the theme picker.
        @Bindable var store = store
        Menu {
            Picker("Theme", selection: $store.themeID) {
                ForEach(["Rams", "Ive", "Pastel", "Eames"], id: \.self) { group in
                    Section(group) {
                        ForEach(Theme.all.filter { $0.group == group }) { t in
                            Text(t.name).tag(t.id)
                        }
                    }
                }
            }
            Divider()
            Button("Choose Tasks folder…", systemImage: "folder", action: pickFolder)
            if case .folder(let url) = store.source {
                Text(url.lastPathComponent)
                Button("Show the demo board", systemImage: "sparkles") { Task { await store.useDemo() } }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .background(store.theme.well, in: Circle())
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Settings")
    }
}

// MARK: - Sections

/// A section heading: bold title, the count next to it, a thick 2px rule under it.
struct SectionHeading: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let count: Int

    var body: some View {
        let theme = store.theme
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(theme.font(22, .semibold))
                Text("\(count)").font(theme.font(22, .semibold)).foregroundStyle(theme.muted)
            }
            Rectangle().fill(theme.ink).frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TodaySection: View {
    @Environment(BoardStore.self) private var store
    let focus: BoardTask?
    let cards: [BoardTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Today", count: cards.count + (focus == nil ? 0 : 1))
            if let focus {
                FocusCard(task: focus)
            }
            if cards.isEmpty && focus == nil {
                EmptyBox(title: "Nothing planned for today", hint: "Pick something from Backlog.")
            } else {
                CardGrid(cards: cards, style: .today)
            }
        }
    }
}

struct CardSection: View {
    let title: String
    let cards: [BoardTask]
    let style: CardStyle
    /// Title and hint for the empty state; nil = no empty state.
    let empty: (String, String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: title, count: cards.count)
            if cards.isEmpty, let empty {
                EmptyBox(title: empty.0, hint: empty.1)
            } else {
                CardGrid(cards: cards, style: style)
            }
        }
    }
}

/// Cards in a grid: as many columns as fit (Today cards at least 160 points
/// wide, Backlog cards 140), so a phone shows two and a Mac window more.
struct CardGrid: View {
    let cards: [BoardTask]
    let style: CardStyle

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: style == .today ? 160 : 140), spacing: 12, alignment: .top)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(cards, id: \.id) { task in
                CardView(task: task, style: style)
            }
        }
    }
}

/// The dashed box that says what's missing and how to fill it.
struct EmptyBox: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let hint: String

    var body: some View {
        let theme = store.theme
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(theme.font(15, .semibold))
            Text(hint).font(theme.font(13)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radiusCard)
                .strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

/// At the bottom: a huge number, "Done today", and the last one finished.
struct DoneSummary: View {
    @Environment(BoardStore.self) private var store
    let done: [BoardTask]

    var body: some View {
        let theme = store.theme
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(done.count)")
                .font(theme.font(56, .semibold))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text("Done today").font(theme.font(15, .semibold))
                if let last = done.first {
                    Text("Last: \(last.title)")
                        .font(theme.font(13))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
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
