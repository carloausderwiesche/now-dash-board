// The capture bar: the one thing every page of the dashboard has. A large
// text field, and above it a strip that says what is happening to what you
// typed. What the strip shows is decided by `CaptureStrip.decide` in
// NowboardKit (a tested pure function); this file only draws it.

#if os(macOS)
    import NowboardKit
    import SwiftUI

    struct CaptureBar: View {
        @Environment(BoardStore.self) private var store
        /// Nil when captures can't be made (demo board, no vault): the bar is then switched off.
        let center: CaptureCenter?
        let unavailable: String?
        /// The page being shown: the field takes the keyboard again when it changes.
        let page: DashboardPage
        @State private var text = ""
        @FocusState private var focused: Bool

        var body: some View {
            let theme = store.theme
            VStack(spacing: 10) {
                // The strip is redrawn every second so a result can fade by itself.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let strip = center.flatMap { CaptureStrip.decide(input($0, now: context.date)) }
                    Group {
                        if let center, let strip {
                            StripView(strip: strip, center: center)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    // Animates when the strip appears, changes or fades away.
                    .animation(.easeOut(duration: 0.25), value: strip)
                }
                field(theme)
            }
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 8)
            .padding(.bottom, 28)
            // Ready to type when the window opens, and when the pages change.
            .onAppear { focused = center != nil }
            .onChange(of: center == nil) { _, none in focused = !none }
            .onChange(of: page) { focused = center != nil }
            // Text that wasn't saved (a capture the disk refused, an answer that wasn't used)
            // comes back into the field, in front of anything typed meanwhile.
            .onChange(of: center?.unsavedText) { _, unsaved in
                guard let unsaved else { return }
                text = text.isEmpty ? unsaved : unsaved + " " + text
                focused = true
            }
        }

        // MARK: Field

        @ViewBuilder
        private func field(_ theme: Theme) -> some View {
            let enabled = center != nil
            let asking = isAsking
            HStack(spacing: 14) {
                TextField(
                    enabled ? (asking ? "Type your answer, or use the buttons above" : "Capture a task, a note, a thought…") : (unavailable ?? ""),
                    text: $text
                )
                .textFieldStyle(.plain)
                .font(theme.font(24, .regular))
                .tracking(Theme.tracking(-0.01, size: 24))
                .focused($focused)
                .disabled(!enabled)
                .onSubmit(send)
                .accessibilityLabel("Capture")
                Image(systemName: "return")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 24)
            .frame(height: 68)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusLarge).strokeBorder(focused ? theme.ink : theme.line, lineWidth: focused ? 1.5 : 1))
            .opacity(enabled ? 1 : 0.6)
        }

        /// Return: answers the open question if there is one, otherwise a new capture.
        /// The field is cleared at once: the pipeline saves the text before anything else.
        private func send() {
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let center, !typed.isEmpty else { return }
            text = ""
            if isAsking { center.answer(typed) } else { center.capture(typed) }
            focused = true
        }

        /// True when the strip is showing a question: only then does Return answer it. (The same
        /// decision that draws the strip, so what you see is what Return does.)
        private var isAsking: Bool {
            guard let center else { return false }
            if case .question? = CaptureStrip.decide(input(center, now: Date())) { return true }
            return false
        }

        // MARK: Strip input

        private func input(_ center: CaptureCenter, now: Date) -> CaptureStripInput {
            var recent = center.recent
            // A suggested task's category name comes from the board.
            if var r = recent, let file = r.entry.taskFile, let task = store.task(file) {
                r.categoryName = category(for: task.area, in: store.settings.categories).name
                recent = r
            }
            return CaptureStripInput(
                pending: center.pending, problem: center.lastProblem, textUnsaved: center.unsavedText != nil,
                openQuestion: center.openQuestion, waitingCount: center.waitingCount, recent: recent, now: now)
        }

    }

    // MARK: - The strip

    private struct StripView: View {
        @Environment(BoardStore.self) private var store
        let strip: CaptureStrip
        let center: CaptureCenter

        var body: some View {
            let theme = store.theme
            switch strip {
            case .sorting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Sorting…")
                }
                .font(theme.font(14, .medium))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: 36)

            case .problem(let message, let textSaved):
                HStack(spacing: 12) {
                    Text(message + (textSaved ? " Your text is saved in the Inbox." : " Your text was not saved: it is back in the field."))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Close") { center.dismissProblem() }
                        .buttonStyle(.pointer)
                        .underline()
                }
                .font(theme.font(13, .medium))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 4))

            case .question(let id, let typed, let question, let others):
                // The dark strip: the question, and the three quick answers.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("“\(typed.trimmingCharacters(in: .whitespacesAndNewlines))”")
                            .lineLimit(1)
                            .foregroundStyle(theme.bg.opacity(0.65))
                        if others > 0 {
                            Text("+\(others) more waiting").foregroundStyle(theme.bg.opacity(0.65))
                        }
                    }
                    .font(theme.font(12))
                    Text(question).font(theme.font(17, .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        quick("Task") { center.answer("It's a task.") }
                        quick("Note") { center.answer("It's a note.") }
                        quick("Skip") { center.skip(id) }
                    }
                }
                .foregroundStyle(theme.bg)
                .padding(16)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusLarge))

            case .result(let id, let message, let canUndo):
                HStack(spacing: 14) {
                    Text(message).frame(maxWidth: .infinity, alignment: .leading)
                    if canUndo {
                        Button("Undo") { center.undo(id) }
                            .buttonStyle(.pointer)
                            .fontWeight(.semibold)
                            .underline()
                    }
                    Button { center.dismissRecent() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.pointer)
                    .foregroundStyle(theme.muted)
                    .accessibilityLabel("Close")
                }
                .font(theme.font(14, .medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 4))
                .overlay(RoundedRectangle(cornerRadius: theme.radiusSmall + 4).strokeBorder(theme.line, lineWidth: 1))

            case .questionLater(_, let message):
                HStack(spacing: 14) {
                    Text(message).frame(maxWidth: .infinity, alignment: .leading)
                    Button { center.dismissRecent() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.pointer)
                    .accessibilityLabel("Close")
                }
                .font(theme.font(14))
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
            }
        }

        /// A light button on the dark strip.
        private func quick(_ title: String, action: @escaping () -> Void) -> some View {
            let theme = store.theme
            return Button(action: action) {
                Text(title)
                    .font(theme.font(14, .semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(theme.bg, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
            }
            .buttonStyle(.pointer)
        }
    }
#endif
