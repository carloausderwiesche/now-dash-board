// The focus session box on the Dashboard: a ring that drains, the time left,
// a task, a length, and the buttons. It only draws and reports clicks: the
// rules are `FocusSession` in NowboardKit and the actions are in
// `FocusSessionModel`.

#if os(macOS)
    import NowboardKit
    import SwiftUI

    struct FocusSessionBox: View {
        @Environment(BoardStore.self) private var store
        @Environment(FocusSessionModel.self) private var model
        @Environment(SiteBlockModel.self) private var siteBlock
        /// What is typed in the custom minutes field.
        @State private var customText = ""
        @FocusState private var customFocused: Bool

        var body: some View {
            let theme = store.theme
            let session = model.session
            // A section like Today and Suggested: the same heading and rule, content on the page.
            DashboardSection(title: "Focus") {
                HStack(alignment: .center, spacing: 20) {
                    ring(session)
                    VStack(alignment: .leading, spacing: 10) {
                        if session.isFinished {
                            Text("Session done").font(theme.font(18, .semibold))
                        }
                        taskPicker(session)
                    }
                }

                if !session.isFinished {
                    lengthChips(session)
                }
                buttons(session)
                siteBlocking()
            }
            .onAppear { syncCustomText() }
            .onChange(of: session.minutes) { syncCustomText() }
            .animation(.easeOut(duration: 0.25), value: session.phase)
            .accessibilityElement(children: .contain)
        }

        // MARK: Ring

        /// The ring: a track, the part of the time left, and the time inside.
        /// It redraws once a second, and only while the session runs: an idle,
        /// paused or finished box is a still picture and costs nothing.
        @ViewBuilder
        private func ring(_ session: FocusSession) -> some View {
            if session.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ringBody(session, at: context.date)
                }
            } else {
                ringBody(session, at: Date())
            }
        }

        private func ringBody(_ session: FocusSession, at now: Date) -> some View {
            let theme = store.theme
            let remaining = session.remaining(at: now)
            return ZStack {
                Circle().stroke(theme.line, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: session.fraction(at: now))
                    // Ink, not the accent: the accent is for NOW on the focus card; this stays calm.
                    .stroke(session.isPaused ? theme.muted : theme.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Each second's step glides instead of jumping.
                    .animation(.linear(duration: 1), value: session.fraction(at: now))
                Text(FocusSession.format(remaining))
                    .font(theme.font(session.minutes >= 60 ? 17 : 22, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(session.isPaused ? theme.muted : theme.ink)
            }
            // A little room so the stroke's outer half doesn't stick out past the column's left edge.
            .padding(3)
            .frame(width: 94, height: 94)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time left")
            .accessibilityValue(FocusSession.format(remaining))
        }

        // MARK: Task

        /// "No task, just focus" or one of the Today cards. Only while idle.
        private func taskPicker(_ session: FocusSession) -> some View {
            let theme = store.theme
            let idle = session.isIdle
            let linked = idle ? model.pickedTaskID : session.taskID
            let label = model.title(of: linked) ?? "No task, just focus"
            return Menu {
                Button("No task, just focus") { model.choice = .none }
                if !model.todayTasks.isEmpty { Divider() }
                ForEach(model.todayTasks, id: \.id) { task in
                    Button(task.title) { model.choice = .task(task.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label).lineLimit(1).truncationMode(.tail)
                    if idle { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)) }
                }
                .font(theme.font(14, .medium))
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            // The menu button would take the accent colour; the picker should read like the other chips.
            .foregroundStyle(theme.ink)
            .tint(theme.ink)
            .disabled(!idle)
            .accessibilityLabel("Task for this session")
        }

        // MARK: Length

        /// 15, 25, 50 and a field for any number of minutes from 1 to 180. Only while idle.
        private func lengthChips(_ session: FocusSession) -> some View {
            let theme = store.theme
            let idle = session.isIdle
            let custom = !FocusSession.presets.contains(session.minutes)
            return HStack(spacing: 8) {
                ForEach(FocusSession.presets, id: \.self) { minutes in
                    let on = session.minutes == minutes
                    Button { model.setLength(minutes) } label: {
                        Text("\(minutes)")
                            .font(theme.font(14, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(on ? theme.ink : theme.muted)
                            .frame(width: 44, height: 32)
                            // The chosen length is a soft tint; the others are plain text.
                            .background(on ? theme.well : .clear, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
                    }
                    .buttonStyle(.pointer)
                    .accessibilityLabel("\(minutes) minutes")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                HStack(spacing: 4) {
                    TextField("…", text: $customText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(theme.font(14, .semibold))
                        .monospacedDigit()
                        .frame(width: 36)
                        .focused($customFocused)
                        .onSubmit(commitCustom)
                        .onChange(of: customFocused) { _, focused in if !focused { commitCustom() } }
                        .accessibilityLabel("Custom minutes, 1 to 180")
                    Text("min").font(theme.font(12)).foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(custom ? theme.well : .clear, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
            }
            .disabled(!idle)
            .opacity(idle ? 1 : 0.5)
        }

        /// Takes the typed minutes if they are a whole number from 1 to 180, otherwise puts back the current length.
        private func commitCustom() {
            if let minutes = FocusSession.parse(minutes: customText) {
                model.setLength(minutes)
            }
            syncCustomText()
        }

        /// Shows the length in the field only when it isn't one of the three presets.
        private func syncCustomText() {
            let minutes = model.session.minutes
            customText = FocusSession.presets.contains(minutes) ? "" : "\(minutes)"
        }

        // MARK: Site blocking

        /// "Block sites" (on by default) and what the helper says: not set up, waiting for approval,
        /// ready, or blocked until a time.
        @ViewBuilder
        private func siteBlocking() -> some View {
            @Bindable var store = store
            let theme = store.theme
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $store.settings.blockSites) {
                    Text("Block sites").font(theme.font(14, .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(theme.ink)
                .accessibilityLabel("Block distracting sites during a session")
                if store.settings.blockSites {
                    HStack(spacing: 10) {
                        Text(siteBlockLine).font(theme.font(13)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                        switch siteBlock.state {
                        case .notSetUp:
                            linkButton("Set up") { siteBlock.setUp() }
                        case .needsApproval:
                            linkButton("Open Settings") { siteBlock.openSettings() }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }

        private var siteBlockLine: String {
            switch siteBlock.state {
            case .notSetUp: "Needs a one-time setup."
            case .needsApproval: "Approve Nowboard in System Settings → Login Items."
            case .ready: "Blocks \(BlockedSites.domains(for: store.settings.blockedSites).count) names while a session runs."
            case .active(let until): "Sites blocked until \(until.formatted(date: .omitted, time: .shortened))."
            case .failed(let message): message
            }
        }

        private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
            let theme = store.theme
            return Button(action: action) {
                Text(title).font(theme.font(13, .semibold)).foregroundStyle(theme.ink).underline()
            }
            .buttonStyle(.pointer)
        }

        // MARK: Buttons

        @ViewBuilder
        private func buttons(_ session: FocusSession) -> some View {
            let theme = store.theme
            HStack(spacing: 10) {
                if session.isFinished {
                    if model.canMarkDone {
                        primary("Mark task done") { model.markTaskDone() }
                    }
                    secondary("Another one") { model.anotherOne() }
                } else {
                    if session.isIdle {
                        primary("Start") {
                            // Minutes typed but not confirmed with Return count too.
                            commitCustom()
                            model.start()
                        }
                    } else if session.isRunning {
                        primary("Pause") { model.pause() }
                    } else {
                        primary("Resume") { model.resume() }
                    }
                    secondary("Reset") { model.reset() }
                        .disabled(session.isIdle)
                        .opacity(session.isIdle ? 0.4 : 1)
                }
                Spacer(minLength: 0)
            }
            .font(theme.font(14, .semibold))
        }

        private func primary(_ title: String, action: @escaping () -> Void) -> some View {
            let theme = store.theme
            return Button(action: action) {
                Text(title)
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
            }
            .buttonStyle(.pointer)
        }

        private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
            let theme = store.theme
            return Button(action: action) {
                Text(title)
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
            }
            .buttonStyle(.pointer)
        }
    }
#endif
