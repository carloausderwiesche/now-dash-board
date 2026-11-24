// Quick add (DESIGN.md): a title, then one row with the category dots and
// the Today / Backlog switch. Return adds, Escape closes. No other fields.
// Sizes from the .quick rules in src/styles.css.

import NowboardKit
import SwiftUI

struct QuickAdd: View {
    @Environment(BoardStore.self) private var store
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
                        .buttonStyle(.plain)
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
                    Text("⌘1–\(cats.count) category")
                    Spacer()
                    Text("↩ add · esc close")
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
            focused = true
        }
        #if os(macOS)
            .onExitCommand { store.adding = false }  // Escape on the Mac
        #endif
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.add(title: title, area: area, status: status)
        store.adding = false
    }
}
