// The detail panel: everything about one task (DESIGN.md, "Detail panel";
// sizes from the .drawer rules in src/styles.css). On the Mac it slides in
// from the right as a floating sheet; on the iPhone it's a sheet from below.
//
// Changes are saved as you make them: the checklist, list and category right
// away, notes a moment after you stop typing, the title when you leave it
// (that renames the file).

import MarkdownUI
import NowboardKit
import SwiftUI

struct DetailPanel: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.openURL) private var openURL
    let id: String
    /// Off only for debug snapshots: ImageRenderer can't draw scroll views.
    var scrolls = true

    /// The task as you edit it. Starts as the stored one; written back on change.
    @State private var draft: BoardTask?
    @State private var title = ""
    @State private var newStep = ""
    @State private var showFile = false
    @State private var notesSave: Task<Void, Never>?
    @FocusState private var titleFocused: Bool
    @State private var editingNotes = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        let theme = store.theme
        if let task = draft ?? store.task(id) {
            let cat = category(for: task.area, in: store.settings.categories)
            VStack(spacing: 0) {
                // .drawer-strip: the category colour along the top.
                Rectangle().fill(cat.color.strong(in: theme)).frame(height: 6)
                let content = VStack(alignment: .leading, spacing: 26) {
                    top(task, cat: cat, theme: theme)
                    titleField(theme: theme)
                    whereRow(task, theme: theme)
                    checklist(task, theme: theme)
                    notes(task, theme: theme)
                    file(task, theme: theme)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                // A click on empty space leaves the notes, so they show rendered.
                .contentShape(Rectangle())
                .onTapGesture { notesFocused = false }
                if scrolls {
                    ScrollView { content }
                } else {
                    content
                    Spacer(minLength: 0)
                }
                footer(task, theme: theme)
            }
            .background(theme.surface)
            .foregroundStyle(theme.ink)
            .onAppear {
                draft = task
                title = task.title
            }
            .onChange(of: titleFocused) { _, focused in
                if !focused { commitTitle() }
            }
            .onDisappear {
                commitTitle()
                flushNotes()
            }
        }
    }

    // MARK: - Parts

    /// Category dots and name; the bin and the close button on the right.
    private func top(_ task: BoardTask, cat: Category, theme: Theme) -> some View {
        HStack(spacing: 10) {
            // Category dots (14pt in 32×36 targets), the chosen one ringed.
            HStack(spacing: 0) {
                ForEach(Array(store.settings.categories.enumerated()), id: \.element.id) { i, c in
                    DotButton(color: c.color.strong(in: theme), name: c.name, box: 32, boxHeight: 36, size: 14,
                              selected: c.id == task.area) {
                        edit { $0.area = c.id }
                    }
                    .accessibilityAddTraits(c.id == task.area ? .isSelected : [])
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
            Text(cat.name).font(theme.font(13)).foregroundStyle(theme.muted)
            Spacer(minLength: 0)
            // One click: the panel closes, the card fades away, Undo brings it back.
            IconButton(icon: TrashIcon(), tip: "Delete file") {
                store.openID = nil
                store.delete(id)
            }
            .accessibilityLabel("Delete task")
            IconButton(icon: CloseIcon(), width: 44, height: 44) {
                store.openID = nil
            }
            .padding(.trailing, -12)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
    }

    /// The title: 30pt, grows to fit, never cut off. Leaving it renames the file.
    private func titleField(theme: Theme) -> some View {
        TextField("Title", text: $title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(theme.font(30, .semibold))
            .tracking(Theme.tracking(-0.02, size: 30))
            .focused($titleFocused)
            .onSubmit { titleFocused = false }
    }

    /// Which list: the Today / Backlog switch, or "Accept to Backlog" for a suggestion.
    @ViewBuilder
    private func whereRow(_ task: BoardTask, theme: Theme) -> some View {
        switch task.status {
        case .suggested:
            HStack(spacing: 10) {
                Text("Suggested").foregroundStyle(theme.muted)
                Button("Accept to Backlog") {
                    store.accept(id)
                    draft?.status = .backlog
                }
                .buttonStyle(.pointer)
                .underline()
            }
            .font(theme.font(13))
        case .today, .backlog:
            Segmented(selection: Binding(get: { task.status }, set: { s in store.move(id, to: s); draft?.status = s }),
                      options: [(.today, "Today"), (.backlog, "Backlog")], theme: theme)
        case .done:
            HStack(spacing: 10) {
                Text("Done").foregroundStyle(theme.muted)
                Button("Reopen") {
                    store.reopen(id)
                    draft?.status = .today
                }
                .buttonStyle(.pointer)
                .underline()
            }
            .font(theme.font(13))
        }
    }

    /// The checklist: round checks like the cards, × to remove a step, a row to add one.
    private func checklist(_ task: BoardTask, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Checklist")
                if !task.items.isEmpty {
                    Text("\(task.items.filter(\.done).count) / \(task.items.count)").foregroundStyle(theme.muted).monospacedDigit()
                }
            }
            .font(theme.font(15, .semibold))
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.ink).frame(height: 2) }

            ForEach(Array(task.items.enumerated()), id: \.offset) { i, item in
                StepRow(item: item, theme: theme,
                        toggle: { edit { $0.items[i].done.toggle() } },
                        remove: { edit { $0.items.remove(at: i) } })
            }
            HStack(spacing: 12) {
                Text("+").font(.system(size: 18)).foregroundStyle(theme.muted).frame(width: 20)
                TextField("Add a step", text: $newStep)
                    .textFieldStyle(.plain)
                    .font(theme.font(15))
                    .onSubmit {
                        let text = newStep.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        edit { $0.items.append(ChecklistItem(text: text, done: false)) }
                        newStep = ""
                    }
            }
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        }
    }

    /// Notes as Obsidian's Reading view shows them (ADR 0014); a tap edits the
    /// markdown as stored, and leaving the editor shows it rendered again.
    private func notes(_ task: BoardTask, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(theme.font(15, .semibold))
            // A real text editor: Return starts a new line, like the Tauri
            // textarea. (A TextField would treat Return as "done".)
            let text = Binding(
                get: { draft?.notes ?? "" },
                set: { value in
                    draft?.notes = value
                    scheduleNotesSave()
                })
            if editingNotes || text.wrappedValue.allSatisfy(\.isWhitespace) {
                editor(text, theme: theme)
            } else {
                Markdown(obsidianToMarkdown(text.wrappedValue, link: store.obsidianURL))
                    .markdownTextStyle {
                        if let name = theme.fontName { FontFamily(.custom(name)) }
                        FontSize(15)
                        ForegroundColor(theme.ink)
                    }
                    .markdownTextStyle(\.link) { ForegroundColor(theme.accent) }
                    .markdownTextStyle(\.code) {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                        BackgroundColor(theme.well)
                    }
                    .frame(maxWidth: .infinity, minHeight: 4 * 22.5 - 24, alignment: .topLeading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(theme.bg, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                    .contentShape(Rectangle())
                    .onTapGesture { editingNotes = true }
                    .accessibilityAction(named: "Edit notes") { editingNotes = true }
            }
        }
    }

    private func editor(_ text: Binding<String>, theme: Theme) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)  // our background, not the system's white
            .font(theme.font(15))
            .lineSpacing(4)
            .foregroundStyle(theme.ink)
            .focused($notesFocused)
            .onAppear { if editingNotes { notesFocused = true } }
            .onChange(of: notesFocused) { _, focused in editingNotes = focused }
            // At least 4 lines (textarea rows=4), growing with the text.
            .frame(minHeight: 4 * 22.5)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text("Anything worth remembering")
                        .font(theme.font(15))
                        .foregroundStyle(theme.muted)
                        .padding(.leading, 5)  // the editor's own line padding
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 9)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
    }

    /// The file name; tap to see the markdown as it's stored.
    private func file(_ task: BoardTask, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showFile.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showFile ? 90 : 0))
                    Text(store.fileURL(task.id).map(displayLocation) ?? "Demo board: \(task.id)")
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.muted)
            }
            .buttonStyle(.pointer)
            .help(store.fileURL(task.id)?.path ?? "")
            if showFile, let url = store.fileURL(task.id), let text = try? readFile(url) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.bg, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
            }
        }
    }

    /// Mark done (solid) and Open in Obsidian (soft), pinned to the bottom.
    private func footer(_ task: BoardTask, theme: Theme) -> some View {
        HStack(spacing: 10) {
            if task.status == .today || task.status == .backlog {
                MarkDoneButton(theme: theme) {
                    store.openID = nil
                    store.finish(id)
                }
            }
            // On the demo board there's no file to open: the button stays,
            // greyed out, and says why.
            let url = store.obsidianURL(task.id)
            ObsidianButton(theme: theme, fills: task.status == .done || task.status == .suggested) {
                if let url { openURL(url) }
            }
            .disabled(url == nil)
            .opacity(url == nil ? 0.5 : 1)
            .help(url == nil ? "Demo board: choose a Tasks folder in Settings first" : "Open this file in Obsidian")
        }
        .padding(.top, 16)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
        .background(theme.surface)
    }

    // MARK: - Saving

    /// Changes the draft and saves it right away.
    private func edit(_ change: (inout BoardTask) -> Void) {
        guard var t = draft ?? store.task(id) else { return }
        change(&t)
        draft = t
        store.update(t)
    }

    /// Notes are saved 0.6s after you stop typing, so each key isn't a write.
    private func scheduleNotesSave() {
        notesSave?.cancel()
        notesSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flushNotes()
        }
    }

    private func flushNotes() {
        notesSave?.cancel()
        guard let d = draft, let stored = store.task(id), stored.notes != d.notes else { return }
        var t = stored
        t.notes = d.notes
        store.update(t)
    }

    private func commitTitle() {
        let new = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored = store.task(id), !new.isEmpty, new != stored.title else { return }
        flushNotes()
        store.rename(id, to: new)
        // The panel follows the new file name (the store moved `openID`).
        draft = store.openID.flatMap(store.task) ?? draft
    }

    private func readFile(_ url: URL) throws -> String {
        let folder = url.deletingLastPathComponent()
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// .btn-primary: on hover a tick slides in and draws itself in front of
/// "Mark done" (.done-tick); pressing shrinks it a little.
private struct MarkDoneButton: View {
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Tick()
                    .trim(from: 0, to: hovering ? 1 : 0)
                    .stroke(theme.bg, style: StrokeStyle(lineWidth: 3.2 * 16 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                    // stroke-dashoffset 0.24s after 0.06s.
                    .animation(.easeOut(duration: 0.24).delay(hovering ? 0.06 : 0), value: hovering)
                    .frame(width: hovering ? 22 : 0, alignment: .leading)
                    .opacity(hovering ? 1 : 0)
                    .clipped()
                Text("Mark done")
            }
            .font(theme.font(15, .semibold))
            .tracking(Theme.tracking(-0.01, size: 15))
            .foregroundStyle(theme.bg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(theme.ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(FooterPress())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

/// .btn-secondary: the well a shade darker on hover, and the ↗ nudges up
/// and right with a small overshoot (.ext).
private struct ObsidianButton: View {
    let theme: Theme
    /// A done or suggested task has no Mark done: this one takes the width.
    let fills: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var pointedAt = false
    /// No hover effect while greyed out (demo board).
    private var hovering: Bool { pointedAt && enabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Open in Obsidian")
                ExternalIcon()
                    .stroke(theme.ink, style: StrokeStyle(lineWidth: 2.2 * 14 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                    .opacity(hovering ? 1 : 0.6)
                    .offset(x: hovering ? 2 : 0, y: hovering ? -2 : 0)
                    .animation(.timingCurve(0.2, 1.4, 0.4, 1, duration: 0.2), value: hovering)
            }
            .font(theme.font(15, .semibold))
            .tracking(Theme.tracking(-0.01, size: 15))
            .foregroundStyle(theme.ink)
            .padding(.leading, 22)
            .padding(.trailing, 20)
            .frame(minHeight: 52)
            .frame(maxWidth: fills ? .infinity : nil)
            // color-mix(ink 7%, well): ink at 7% laid over the well.
            .background {
                ZStack {
                    Capsule().fill(theme.well)
                    Capsule().fill(theme.ink.opacity(hovering ? 0.07 : 0))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(FooterPress())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { pointedAt = h } }
    }
}

/// `:active { transform: scale(0.98) }` with the hand cursor.
private struct FooterPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .cursor(.pointingHand)
    }
}

/// One checklist step: a round check, the text (struck through when done), ×.
private struct StepRow: View {
    let item: ChecklistItem
    let theme: Theme
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(item.done ? theme.accent : .clear)
                    Circle().strokeBorder(item.done ? theme.accent : theme.ink, lineWidth: 1.5)
                    if item.done {
                        Tick().stroke(theme.onAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).padding(4)
                    }
                }
                .frame(width: 20, height: 20)
                .scaleEffect(item.done ? 1.08 : 1)
                .animation(.easeOut(duration: 0.2), value: item.done)
            }
            .buttonStyle(.pointer)
            .accessibilityLabel(item.done ? "Done" : "Not done")
            Text(item.text)
                .font(theme.font(15))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? theme.muted : theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.pointer)
            .foregroundStyle(theme.muted)
            .opacity(showRemove ? 1 : 0)
            .accessibilityLabel("Remove step: \(item.text)")
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .onHover { hovering = $0 }
    }

    private var showRemove: Bool {
        #if os(iOS)
            true
        #else
            hovering
        #endif
    }
}

/// The pill-shaped switch (.segmented): Today / Backlog, here and in quick add.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, name in
                let on = value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(name)
                        .font(theme.font(12, .medium))
                        .foregroundStyle(on ? theme.ink : theme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if on {
                                Capsule().fill(theme.surface).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.pointer)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(theme.well, in: Capsule())
        .fixedSize()
    }
}
