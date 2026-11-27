// The Mac app's window: a Dashboard (DESIGN.md, "Dashboard"). A header with
// the day, a switch between three pages, and the capture bar
// pinned at the bottom of every page. Only the task lists and the Inbox list
// scroll; everything else stays where it is.
//
// The iPhone app keeps the board as its one screen: this file is macOS only.

#if os(macOS)
    import NowboardKit
    import SwiftUI

    /// The three pages of the dashboard.
    enum DashboardPage: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case tasks = "Tasks"
        case inbox = "Inbox"

        var id: String { rawValue }
    }

    struct DashboardRoot: View {
        @Environment(BoardStore.self) private var store
        @Environment(\.scenePhase) private var scenePhase
        @State private var page: DashboardPage = DashboardRoot.firstPage
        @State private var pickingFolder = false
        /// The capture machinery for the real vault. Nil on the demo board, or
        /// when the Tasks folder isn't in an Obsidian vault.
        @State private var center: CaptureCenter?
        /// The tidy-up of the vault (the Inbox page's "Tidy vault"); nil without a vault.
        @State private var tidy: TidyModel?
        /// The category ids the classifier may choose from, kept up to date from the settings.
        @State private var categoryIds = CategoryIds()
        /// The focus session (its box is on the Dashboard page; it keeps running on the other pages).
        @State private var focus = FocusSessionModel()
        /// What the Teams box shows (read from the Dock badge only while the box is on screen).
        @State private var teams = TeamsUnreadModel()
        /// Blocking distracting sites during a focus session (through a helper the user approves once).
        @State private var siteBlock = SiteBlockModel()

        /// Debug builds can open on another page: `-page tasks`.
        private static var firstPage: DashboardPage {
            #if DEBUG
                if let name = DebugSnapshot.argument("page"), let page = DashboardPage.allCases.first(where: { $0.rawValue.lowercased() == name }) {
                    return page
                }
            #endif
            return .dashboard
        }

        var body: some View {
            let theme = store.theme
            VStack(spacing: 0) {
                DashboardHeader(page: $page, waiting: center?.waitingCount ?? 0)
                // The pages. The Undo pill floats over them, above the capture bar.
                ZStack {
                    switch page {
                    case .dashboard: DashboardPageView()
                    case .tasks: BoardView(embedded: true)
                    case .inbox: InboxPage(center: center, tidy: tidy, sessionRunning: focus.session.isRunning)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { UndoPill() }
                CaptureBar(center: center, unavailable: unavailableMessage, page: page, sessionRunning: focus.session.isRunning)
            }
            .background(theme.bg.ignoresSafeArea())
            // No round window buttons: the dashboard is one window that fills the top (WindowChrome.swift).
            .background(HideWindowButtons())
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            .animation(.easeOut(duration: 0.45), value: theme.id)
            // No blue focus ring on whichever button has keyboard focus.
            .focusEffectDisabled()
            // The header runs up under the (hidden) title bar; it leaves room for the window buttons itself.
            .ignoresSafeArea(edges: .top)
            // Popovers and menus are placed in this space (it's the whole window).
            .coordinateSpace(name: rootSpace)
            .overlay { MacOverlays() }
            .overlay { SettingsPopover(pickFolder: { pickingFolder = true }) }
            .overlay { CardMenuLayer() }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { Task { await store.use(folder: url) } }
            }
            .task { await store.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reload() } }
            }
            // A capture centre for the vault the Tasks folder is in, made again when the folder changes.
            .task(id: captureKey) { makeCenter() }
            .onAppear {
                categoryIds.set(store.settings.categories.map(\.id))
                // Before `attach`, which reports a restored running session right away.
                focus.onRunningEndChange = { end in siteBlock.update(until: end, entries: blockEntries(end)) }
                focus.attach(to: store)
                #if DEBUG
                    focus.applyDebugArguments()
                #endif
            }
            .environment(focus)
            .environment(teams)
            .environment(siteBlock)
            // Switching blocking on or off, or changing the list, while a session runs counts at once.
            .onChange(of: store.settings.blockSites) { siteBlock.update(until: focus.runningEnd, entries: blockEntries(focus.runningEnd)) }
            .onChange(of: store.settings.blockedSites) { siteBlock.update(until: focus.runningEnd, entries: blockEntries(focus.runningEnd)) }
            .onChange(of: store.settings.categories.map(\.id)) { _, ids in categoryIds.set(ids) }
        }

        // MARK: - Site blocking

        /// The sites to block for a session ending at `end`: the person's list if blocking is on and a
        /// session is running, nothing otherwise (which unblocks).
        private func blockEntries(_ end: Date?) -> [String] {
            end != nil && store.settings.blockSites ? store.settings.blockedSites : []
        }

        // MARK: - Capture centre

        /// Changes when the Tasks folder changes.
        private var captureKey: String {
            switch store.source {
            case .demo: "demo"
            case .folder(let url): url.path
            }
        }

        /// Why the capture bar is switched off, or nil when it works.
        private var unavailableMessage: String? {
            guard center == nil else { return nil }
            if case .folder(let url) = store.source, vaultRoot(of: url) == nil {
                return "The Tasks folder isn't inside an Obsidian vault, so captures can't be filed"
            }
            return "Choose a Tasks folder in Settings to capture"
        }

        private func makeCenter() {
            center = nil
            tidy = nil
            #if DEBUG
                // `-demoCapture true`: a throwaway vault and a scripted classifier, for snapshots.
                if store.isDemo, DebugSnapshot.argument("demoCapture") == "true" {
                    center = DebugDemoCapture.makeCenter()
                    return
                }
            #endif
            guard case .folder(let url) = store.source, let vault = vaultRoot(of: url) else { return }
            let ids = categoryIds
            let config = VaultConfig.load(vault: vault, tasksFolder: url)
            let cli = ClaudeSupport.classifier(claudePath: { DeviceSettings.load().claudePath })
            let advisor = ClaudeCLIVaultAdvisor(cli: cli)
            let made = CaptureCenter(
                config: config, classifier: cli, categoryIds: { ids.get() }, guide: GuideMaintainer(config: config, advisor: advisor))
            center = made
            tidy = TidyModel(changes: VaultChanges(config: config), advisor: advisor)
            // Captures that couldn't be classified before (offline…) get another go, once.
            made.retry()
        }
    }

    /// The category ids as a thread-safe box: the classifier asks for them from a background thread.
    final class CategoryIds: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func set(_ new: [String]) { lock.withLock { ids = new } }
        func get() -> [String] { lock.withLock { ids } }
    }

    // MARK: - Header

    /// The day number with weekday and month, and on the right the page switch.
    struct DashboardHeader: View {
        @Environment(BoardStore.self) private var store
        @Binding var page: DashboardPage
        /// Captures waiting for an answer: the Inbox tab's badge.
        let waiting: Int

        var body: some View {
            let theme = store.theme
            HStack(alignment: .bottom, spacing: 40) {
                // The day, like the board's header but a little smaller.
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(Date.now, format: .dateTime.day())
                        .font(theme.font(72, .semibold))
                        .tracking(Theme.tracking(-0.05, size: 72))
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.vertical, theme.lineBoxTrim(72, lineHeight: 0.8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date.now, format: .dateTime.weekday(.wide)).fontWeight(.semibold)
                        Text(Date.now, format: .dateTime.month(.wide)).foregroundStyle(theme.muted)
                    }
                    .font(theme.font(15))
                    .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PageSwitch(page: $page, waiting: waiting)
                    Rectangle().fill(theme.line).frame(width: 1, height: 20).padding(.horizontal, 10)
                    FilterDots()
                    SettingsButton()
                }
                .fixedSize()
                // The settings popover opens under this.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(rootSpace)) } action: { store.settingsAnchor = $0 }
            }
            // The window buttons are hidden; the 34pt on top is the strip that still drags the window.
            .padding(.top, 34)
            .padding(.horizontal, 48)
            .padding(.bottom, 14)
        }
    }

    /// Dashboard | Tasks | Inbox, one of them selected. Inbox shows how many captures wait for an answer.
    struct PageSwitch: View {
        @Environment(BoardStore.self) private var store
        @Binding var page: DashboardPage
        let waiting: Int

        var body: some View {
            let theme = store.theme
            HStack(spacing: 2) {
                ForEach(DashboardPage.allCases) { item in
                    let on = item == page
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { page = item }
                    } label: {
                        HStack(spacing: 7) {
                            Text(item.rawValue)
                            if item == .inbox, waiting > 0 {
                                Text("\(waiting)")
                                    .font(theme.font(11, .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.onAccent)
                                    .padding(.horizontal, 6)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(theme.accent, in: Capsule())
                                    .accessibilityLabel("\(waiting) waiting for an answer")
                            }
                        }
                        .font(theme.font(14, .medium))
                        .foregroundStyle(on ? theme.ink : theme.muted)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(on ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pointer)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(theme.well, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 5))
        }
    }
#endif
