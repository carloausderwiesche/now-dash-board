// The dashboard's own pages: Dashboard (Today, Suggested, done today) and
// Inbox (the captures). The third page, Tasks, is the board as it is.

#if os(macOS)
    import AppKit
    import NowboardKit
    import SwiftUI

    // MARK: - Boxes

    /// A box for the dashboard's right column (Teams, music, a calendar…).
    /// The column only appears once one is registered, and the Today grid uses
    /// the full width until then. No placeholders: only real boxes are listed.
    struct DashboardBox: Identifiable {
        let id: String
        let content: @MainActor () -> AnyView
    }

    enum DashboardBoxes {
        /// The boxes to show, in order. Later packages add theirs here.
        @MainActor static var registered: [DashboardBox] {
            [
                DashboardBox(id: "focus-session") { AnyView(FocusSessionBox()) },
                DashboardBox(id: "teams-unread") { AnyView(TeamsBox()) },
            ]
        }
    }

    /// The look every box on the Dashboard shares: the same heading as Today and
    /// Suggested (22pt title, a rule under it), and the content on the page itself.
    /// No card, no fill, no border: boxes are sections, so the page stays calm.
    /// Later boxes (chat, calendar, music) use this too.
    struct DashboardSection<Content: View>: View {
        let title: String
        var count: Int? = nil
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: title, count: count)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Dashboard page

    struct DashboardPageView: View {
        @Environment(BoardStore.self) private var store
        @Namespace private var flight

        var body: some View {
            let boxes = DashboardBoxes.registered
            HStack(alignment: .top, spacing: 40) {
                // The left column scrolls; the header and the capture bar don't.
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        if let error = store.error { ErrorBar(message: error) }
                        let lists = store.lists
                        CardSection(
                            title: "Today", cards: lists.today, style: .today, narrow: false, flight: flight,
                            empty: ("Nothing planned for today", "Send a card to Today from Suggested, or from the Tasks page"),
                            dragEnabled: false)
                        if !lists.suggested.isEmpty { SuggestedRows(tasks: lists.suggested) }
                        DonePill(count: lists.doneToday.count)
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The cards measure themselves in this space (the board's, so a finished card flies to the pill).
                    .coordinateSpace(name: boardSpace)
                }
                .scrollIndicators(.hidden)
                if !boxes.isEmpty {
                    // The same gap between sections as in the left column.
                    VStack(alignment: .leading, spacing: 36) {
                        ForEach(boxes) { $0.content() }
                    }
                    // Same top padding as the left column: the first heading and its rule line up with "Today".
                    .frame(width: 380, alignment: .top)
                    .padding(.trailing, 48)
                    .padding(.top, 14)
                }
            }
        }
    }

    /// Suggested tasks as rows: Today and Dismiss on each. Dismiss deletes the
    /// file and offers Undo, like everywhere else (ADR 0010).
    struct SuggestedRows: View {
        @Environment(BoardStore.self) private var store
        let tasks: [BoardTask]

        var body: some View {
            let theme = store.theme
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Suggested", count: tasks.count)
                ForEach(tasks, id: \.id) { task in
                    HStack(spacing: 12) {
                        CategoryDot(color: category(for: task.area, in: store.settings.categories).color.strong(in: theme), size: 10)
                        Button { store.openID = task.id } label: {
                            Text(task.title)
                                .font(theme.font(16))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pointer)
                        Button("Today") { withAnimation(.easeOut(duration: 0.3)) { store.moveToTop(task.id, of: .today) } }
                            .buttonStyle(.pointer)
                            .font(theme.font(13, .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(theme.well, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                            .help("Plan it for today")
                        Button("Dismiss") { store.delete(task.id) }
                            .buttonStyle(.pointer)
                            .font(theme.font(13, .medium))
                            .foregroundStyle(theme.muted)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .help("Dismiss (deletes the file, Undo is offered)")
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                    .opacity(store.deleting.contains(task.id) ? 0 : 1)
                }
            }
        }
    }

    /// "3 done today": a small pill. Finished cards fly to it.
    struct DonePill: View {
        @Environment(BoardStore.self) private var store
        let count: Int

        var body: some View {
            let theme = store.theme
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(theme.font(16, .semibold))
                    .monospacedDigit()
                    // Where finished cards fly to.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(boardSpace)) } action: { store.doneTarget = $0 }
                Text("done today").foregroundStyle(theme.muted)
            }
            .font(theme.font(14, .medium))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(theme.well, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Inbox page

    struct InboxPage: View {
        @Environment(BoardStore.self) private var store
        let center: CaptureCenter?
        /// The AI tidy-up (nil without a vault).
        let tidy: TidyModel?
        /// A focus session is running: tidying waits until it ends.
        let sessionRunning: Bool

        var body: some View {
            let theme = store.theme
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let rows = center.map { InboxList.ordered($0.entries) } ?? []
                    SectionHeading(title: "Inbox", count: rows.count)
                    if let tidy { TidyPanel(tidy: tidy, sessionRunning: sessionRunning) }
                    if rows.isEmpty {
                        EmptyBox(
                            title: center == nil ? "Captures need a Tasks folder" : "No captures yet",
                            hint: center == nil ? "Choose one in Settings" : "Type in the bar below. Everything you type is saved here first")
                    } else if let center {
                        ForEach(rows, id: \.id) { InboxRow(entry: $0, center: center) }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(theme.ink)
        }
    }

    /// One capture: when, what was typed, what became of it, and Undo where that works.
    struct InboxRow: View {
        @Environment(BoardStore.self) private var store
        let entry: InboxEntry
        let center: CaptureCenter

        var body: some View {
            let theme = store.theme
            let waiting = entry.outcome == .waitingForAnswer
            HStack(alignment: .top, spacing: 16) {
                Text(timeLabel)
                    .font(theme.font(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
                    .frame(width: 76, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(theme.font(16))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(InboxText.outcome(entry, categoryName: categoryName))
                        .font(theme.font(13))
                        .foregroundStyle(waiting ? theme.accent : theme.muted)
                    if waiting, let question = entry.followUp {
                        Text(question).font(theme.font(13, .medium))
                    }
                }
                if opensSomething {
                    Button("Open") { open() }
                        .buttonStyle(.pointer)
                        .font(theme.font(12, .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                }
                if InboxText.canUndo(entry) {
                    Button("Undo") { center.undo(entry.id) }
                        .buttonStyle(.pointer)
                        .font(theme.font(12, .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .help("Take back what was filed for this capture")
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }

        /// `13:05`, or `Wed 13:05` for another day.
        private var timeLabel: String {
            guard let stamp = entry.captured, stamp.count >= 16 else { return "" }
            let day = String(stamp.prefix(10))
            let time = String(stamp.suffix(5))
            if day == String(TaskFormat.timestamp(.now).prefix(10)) { return time }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            guard let date = f.date(from: day) else { return time }
            return date.formatted(.dateTime.weekday(.abbreviated).day()) + " " + time
        }

        /// The category of a suggested task, by looking the task up on the board.
        private var categoryName: String? {
            guard let file = entry.taskFile, let task = store.task(file) else { return nil }
            return category(for: task.area, in: store.settings.categories).name
        }

        /// Only if there is a file to open (the task still exists, or the note path is usable).
        private var opensSomething: Bool {
            if let file = entry.taskFile { return store.task(file) != nil }
            return entry.notePath != nil
        }

        /// A task opens in the board's panel; a note opens in Obsidian.
        private func open() {
            if let file = entry.taskFile {
                store.openID = file
            } else if let path = entry.notePath {
                var parts = URLComponents()
                parts.scheme = "obsidian"
                parts.host = "open"
                parts.queryItems = [URLQueryItem(name: "path", value: center.config.vault.appendingPathComponent(path).path)]
                if let url = parts.url { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: - Tidy vault

    /// "Tidy vault": the AI proposes where the notes filed in the Inbox belong; the person approves; each
    /// change can be undone. Never automatic (docs/vault-changes.md, section 5).
    struct TidyPanel: View {
        @Environment(BoardStore.self) private var store
        let tidy: TidyModel
        let sessionRunning: Bool

        var body: some View {
            let theme = store.theme
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button { tidy.propose() } label: {
                        Text(tidy.phase == .proposing ? "Looking…" : "Tidy vault")
                            .font(theme.font(14, .semibold))
                            .foregroundStyle(theme.bg)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
                            .opacity(canStart ? 1 : 0.4)
                    }
                    .buttonStyle(.pointer)
                    .disabled(!canStart)
                    Text(hint).font(theme.font(13)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                // While the AI is thinking the person can still stop waiting.
                if tidy.phase == .proposing {
                    Button("Stop") { tidy.cancel() }
                        .buttonStyle(.pointer).font(theme.font(13, .medium)).foregroundStyle(theme.muted)
                }
                if case .failed(let why) = tidy.phase {
                    Text(why).font(theme.font(13, .medium)).foregroundStyle(theme.accent).textSelection(.enabled)
                }
                if tidy.phase == .review || tidy.phase == .applying { reviewList(theme) }
                if tidy.dropped > 0, tidy.phase == .review {
                    Text("\(tidy.dropped) suggestion\(tidy.dropped == 1 ? " was" : "s were") unusable and left out.")
                        .font(theme.font(12)).foregroundStyle(theme.muted)
                }
                if let message = tidy.message {
                    Text(message).font(theme.font(13, .medium)).fixedSize(horizontal: false, vertical: true)
                }
                if !tidy.recent.isEmpty { recentList(theme) }
            }
            .padding(.bottom, 8)
        }

        private var canStart: Bool {
            !sessionRunning && (tidy.phase == .idle || tidy.phase == .review || isFailed)
        }

        private var isFailed: Bool {
            if case .failed = tidy.phase { return true }
            return false
        }

        private var hint: String {
            sessionRunning
                ? "Not during a focus session."
                : "Proposes where the notes in the Inbox folder belong. Nothing changes until you approve, and every change can be undone."
        }

        private func reviewList(_ theme: Theme) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tidy.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Button { tidy.toggle(item.id) } label: {
                            Image(systemName: item.approved ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(item.problem == nil ? theme.ink : theme.muted)
                        }
                        .buttonStyle(.pointer)
                        .disabled(item.problem != nil)
                        .accessibilityLabel(item.approved ? "Approved" : "Not approved")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.operation.summary).font(theme.font(14, .medium))
                            if let reason = item.operation.reason { Text(reason).font(theme.font(12)).foregroundStyle(theme.muted) }
                            // What would be added is shown in full: approving means reading it.
                            if item.operation.kind == .append, let text = item.operation.text {
                                Text("Adds: “\(text.trimmingCharacters(in: .whitespacesAndNewlines))”")
                                    .font(theme.font(12))
                                    .lineLimit(6)
                                    .padding(8)
                                    .background(theme.hover, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                            }
                            if let problem = item.problem {
                                Text("Can't be done: \(problem)").font(theme.font(12)).foregroundStyle(theme.accent)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 10) {
                    Button { tidy.applyApproved() } label: {
                        Text(tidy.phase == .applying ? "Working…" : "Apply \(tidy.approvedCount) change\(tidy.approvedCount == 1 ? "" : "s")")
                            .font(theme.font(14, .semibold))
                            .foregroundStyle(theme.bg)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
                            .opacity(tidy.approvedCount > 0 && tidy.phase == .review ? 1 : 0.4)
                    }
                    .buttonStyle(.pointer)
                    .disabled(tidy.approvedCount == 0 || tidy.phase != .review)
                    Button("Cancel") { tidy.cancel() }
                        .buttonStyle(.pointer)
                        .font(theme.font(14, .medium))
                        .foregroundStyle(theme.muted)
                        .disabled(tidy.phase != .review)
                }
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusLarge).strokeBorder(theme.line, lineWidth: 1))
        }

        private func recentList(_ theme: Theme) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT CHANGES")
                    .font(theme.font(11, .semibold))
                    .tracking(Theme.tracking(0.14, size: 11))
                    .foregroundStyle(theme.muted)
                ForEach(tidy.recent, id: \.id) { record in
                    HStack(spacing: 10) {
                        Text(record.operation.summary)
                            .font(theme.font(13))
                            .strikethrough(record.undone)
                            .foregroundStyle(record.undone ? theme.muted : theme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if record.linksChanged > 0 {
                            Text("\(record.linksChanged) link\(record.linksChanged == 1 ? "" : "s") updated").font(theme.font(12)).foregroundStyle(theme.muted)
                        }
                        if !record.undone {
                            Button("Undo") { tidy.undo(record.id) }
                                .buttonStyle(.pointer)
                                .font(theme.font(12, .medium))
                                .frame(height: 28)
                                .disabled(tidy.isBusy)
                        }
                    }
                }
            }
        }
    }
#endif
