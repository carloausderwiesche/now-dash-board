// Quick add (DESIGN.md): a title, then one row with the category dots and
// the Today / Backlog switch. Return adds, Escape closes. No other fields.
// Sizes from the .quick rules in src/styles.css.

import NowboardKit
import SwiftUI

struct QuickAdd: View {
    @Environment(BoardStore.self) private var store
    /// How to close: the board's quick add (nil) or the floating ⌥ Space panel.
    var onClose: (() -> Void)? = nil
    /// The floating panel passes ⌘1–⌘6 in through this (see QuickKeys).
    var keys: QuickKeys? = nil
    @State private var title = ""
    @State private var area = ""
    @State private var status: TaskStatus = .today
    @FocusState private var focused: Bool

    var body: some View {
        let theme = store.theme
        let cats = store.settings.categories
        let chosen = category(for: area, in: cats)
        VStack(spacing: 0) {
            // .quick-top: the chosen category's dot, then the title field.
            HStack(spacing: 14) {
                CategoryDot(color: chosen.color.strong(in: theme), size: 10)
                TextField("What needs doing?", text: $title)
                    .textFieldStyle(.plain)
                    .font(theme.font(22, .medium))
                    .tracking(Theme.tracking(-0.01, size: 22))
                    .focused($focused)
                    .onSubmit(add)
                    .submitLabel(.done)
                    // Tab switches Today / Backlog (instead of moving the focus),
                    // Esc closes, like the Tauri quick add.
                    .onKeyPress(.tab) {
                        withAnimation(.easeOut(duration: 0.2)) { status = status == .today ? .backlog : .today }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
            }
            .padding(.top, 22)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            // .quick-opts: category dots (with the chosen one's name) and the switch.
            HStack(spacing: 14) {
                HStack(spacing: 2) {
                    ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                        let on = c.id == chosen.id
                        Button {
                            area = c.id
                        } label: {
                            Circle().fill(c.color.strong(in: theme)).frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(c.color.strong(in: theme), lineWidth: 1.5).padding(-4.5).opacity(on ? 1 : 0))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pointer)
                        .help(c.name)
                        .accessibilityLabel(c.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        // ⌘1–⌘6 pick a category, like the Tauri app.
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    }
                    Text(chosen.name)
                        .font(theme.font(13, .medium))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .padding(.leading, 10)
                }
                .padding(.leading, -11)
                Spacer(minLength: 0)
                Segmented(selection: $status, options: [(.today, "Today"), (.backlog, "Backlog")], theme: theme)
            }
            .padding(.top, 4)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)

            #if os(macOS)
                // .quick-hint: the keys, split like the row above.
                HStack {
                    Text("⌘1–\(cats.count) category · tab Today/Backlog")
                    Spacer()
                    Text(onClose == nil ? "↩ add · esc close" : "⌥ Space anywhere · ↩ add · esc close")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.muted)
                .padding(.vertical, 10)
                .padding(.horizontal, 22)
                .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
            #endif
        }
        .foregroundStyle(theme.ink)
        .background(theme.surface)
        .onAppear {
            area = store.filter ?? cats.first?.id ?? "personal"
            keys?.onCommandDigit = { n in
                if n >= 1 && n <= cats.count { area = cats[n - 1].id }
            }
        }
        // The cursor goes straight into the title. Set a moment after the view
        // is in its window: in `onAppear` it's too early and gets lost.
        .defaultFocus($focused, true)
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        #if DEBUG
            .onChange(of: focused) { _, f in
                if ProcessInfo.processInfo.arguments.contains("-focusdebug") { print("QUICKADD focused:", f) }
            }
        #endif
        #if os(macOS)
            .onExitCommand { close() }  // Escape on the Mac
        #endif
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.add(title: title, area: area, status: status)
        title = ""
        close()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            store.adding = false
        }
    }
}

/// Keys the floating panel catches itself. The app isn't active while you
/// type into the ⌥ Space panel, so ⌘-shortcuts never reach SwiftUI's
/// `keyboardShortcut`; the panel sees them first and passes ⌘1–⌘6 on here.
@MainActor
final class QuickKeys {
    var onCommandDigit: ((Int) -> Void)?
}
