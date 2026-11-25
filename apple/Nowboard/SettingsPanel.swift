// Settings (DESIGN.md, Settings; sizes from .popover in src/styles.css):
// theme, card size, categories, the Tasks folder and the daily-note query.
// On the Mac a themed popover under the settings button, on the iPhone a sheet.

import NowboardKit
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct SettingsPanel: View {
    @Environment(BoardStore.self) private var store
    var pickFolder: () -> Void
    @State private var copied = false

    var body: some View {
        // `@Bindable` lets the pickers write to the store's settings through `$store`.
        @Bindable var store = store
        let theme = store.theme
        VStack(alignment: .leading, spacing: 18) {
            Field(label: "Theme") {
                Picker("Theme", selection: $store.settings.theme) {
                    ForEach(["Rams", "Ive", "Pastel", "Eames"], id: \.self) { group in
                        Section(group) {
                            ForEach(Theme.all.filter { $0.group == group }) { t in
                                Text(t.name).tag(t.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Field(label: "Cards") {
                Segmented(selection: $store.settings.compact, options: [(false, "Roomy"), (true, "Compact")], theme: theme)
            }
            Field(label: "Categories") {
                CategoryEditor()
            }
            Field(label: "Tasks folder") {
                folder(theme: theme)
            }
            Field(label: "Finished tasks in your daily note") {
                query(theme: theme)
            }
        }
        .padding(18)
        .foregroundStyle(theme.ink)
    }

    @ViewBuilder
    private func folder(theme: Theme) -> some View {
        if case .folder(let url) = store.source {
            Text(url.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.muted)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                SmallButton(title: "Choose…", action: choose)
                SmallButton(title: "Show the demo board") {
                    store.showingSettings = false
                    Task { await store.useDemo() }
                }
            }
        } else {
            Text("Demo board: nothing is saved yet.")
                .font(theme.font(12))
                .foregroundStyle(theme.muted)
            SmallButton(title: "Choose Tasks folder…", action: choose)
        }
    }

    private func choose() {
        store.showingSettings = false
        pickFolder()
    }

    @ViewBuilder
    private func query(theme: Theme) -> some View {
        let folder: String =
            if case .folder(let url) = store.source { vaultRelativePath(of: url) } else { "Notes/Tasks" }
        let text = doneQuery(tasksFolder: folder)
        Text("Nowboard never writes into your notes. To list a day's finished tasks, add this to your daily-note template (needs the Dataview plugin):")
            .font(theme.font(12))
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.hover, in: RoundedRectangle(cornerRadius: 8))
        SmallButton(title: copied ? "Copied" : "Copy") {
            #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #else
                UIPasteboard.general.string = text
            #endif
            copied = true
        }
    }
}

/// .field-group: a small caps label over its control.
private struct Field<Content: View>: View {
    @Environment(BoardStore.self) private var store
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(store.theme.font(11, .semibold))
                .tracking(Theme.tracking(0.14, size: 11))
                .foregroundStyle(store.theme.muted)
            content
        }
    }
}

/// .btn-small: a round outlined button, tinted on hover.
struct SmallButton: View {
    @Environment(BoardStore.self) private var store
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let theme = store.theme
        Button(action: action) {
            Text(title)
                .font(theme.font(13, .medium))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(hovering ? theme.hover : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pointer)
        .onHover { hovering = $0 }
    }
}

// MARK: - Categories

/// The category list: tap a dot for the colour palette, rename inline, drag
/// the ⠿ grip to reorder (the order of the dots everywhere), × to delete (at
/// least one stays), "+ Category" up to six. Saved to `.nowboard.json`.
private struct CategoryEditor: View {
    @Environment(BoardStore.self) private var store
    /// The category whose colour palette is open.
    @State private var picking: String?
    /// The row being dragged by its grip: where it started and how far it moved.
    @State private var drag: (id: String, from: Int, dy: CGFloat)?
    /// One row plus the gap between rows: how far a row moves per slot.
    private let step: CGFloat = 36 + 6

    var body: some View {
        let theme = store.theme
        let cats = store.settings.categories
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                CategoryRow(
                    category: c, canRemove: cats.count > 1, lifted: drag?.id == c.id, sorting: drag != nil,
                    picking: Binding(get: { picking == c.id }, set: { picking = $0 ? c.id : nil }),
                    change: { edit in update(c.id, edit) },
                    remove: {
                        picking = nil
                        store.setCategories(cats.filter { $0.id != c.id })
                    },
                    grip: grip(index: i, id: c.id, count: cats.count)
                )
                .offset(y: offset(i, c.id))
                // The dragged row follows the pointer exactly; the others slide aside.
                .animation(drag?.id == c.id ? nil : .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2), value: offset(i, c.id))
                // The open palette and the dragged row float over the rows below.
                .zIndex(picking == c.id || drag?.id == c.id ? 1 : 0)
                .accessibilityAction(named: "Move up") { move(from: i, to: i - 1) }
                .accessibilityAction(named: "Move down") { move(from: i, to: i + 1) }
            }
            if cats.count < maxCategories {
                Button {
                    store.setCategories(cats + [newCategory(after: cats)])
                } label: {
                    Text("+ Category")
                        .font(theme.font(13))
                        .foregroundStyle(theme.muted)
                        .frame(height: 36)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pointer)
                .padding(.leading, -8)
            }
        }
    }

    private func update(_ id: String, _ edit: (inout Category) -> Void) {
        var cats = store.settings.categories
        guard let i = cats.firstIndex(where: { $0.id == id }) else { return }
        edit(&cats[i])
        store.setCategories(cats)
    }

    private func move(from: Int, to: Int) {
        var cats = store.settings.categories
        guard from != to, cats.indices.contains(from), cats.indices.contains(to) else { return }
        // `move(fromOffsets:toOffset:)` counts the target before removing, hence +1 going down.
        cats.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        store.setCategories(cats)
    }

    /// The slot the dragged row is over.
    private var target: Int? {
        drag.map { d in d.from + Int((d.dy / step).rounded()) }
    }

    /// How far a row is pushed while dragging (like the Tauri popover).
    private func offset(_ i: Int, _ id: String) -> CGFloat {
        guard let drag, let to = target else { return 0 }
        if id == drag.id { return drag.dy }
        if drag.from < i && i <= to { return -step }
        if to <= i && i < drag.from { return step }
        return 0
    }

    private func grip(index i: Int, id: String, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                picking = nil
                // Kept between the first and the last slot, never past them.
                let dy = min(max(v.translation.height, -CGFloat(i) * step), CGFloat(count - 1 - i) * step)
                drag = (id, i, dy)
            }
            .onEnded { _ in
                let to = target ?? i
                // Swapping the order and clearing the offsets in one step,
                // without animation: every row is already where it ends up.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    drag = nil
                    move(from: i, to: to)
                }
            }
    }
}

/// .cat-row: grip (in the left margin, on hover), colour dot, name, ×.
private struct CategoryRow<G: Gesture>: View {
    @Environment(BoardStore.self) private var store
    let category: Category
    let canRemove: Bool
    let lifted: Bool
    let sorting: Bool
    @Binding var picking: Bool
    let change: ((inout Category) -> Void) -> Void
    let remove: () -> Void
    let grip: G
    @State private var hovering = false

    var body: some View {
        let theme = store.theme
        let color = category.color.strong(in: theme)
        HStack(spacing: 8) {
            Button {
                picking.toggle()
            } label: {
                Circle().fill(color).frame(width: 14, height: 14)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pointer)
            .accessibilityLabel("Choose colour for \(category.name)")
            TextField("Name", text: Binding(get: { category.name }, set: { name in change { $0.name = name } }))
                .textFieldStyle(.plain)
                .font(theme.font(14))
                .frame(height: 36)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.line).frame(height: 1).opacity(lifted ? 0 : 1)
                }
                .accessibilityLabel("Category name")
            if canRemove {
                // The system tooltip (like the CSS `title`): the popover would cut ours off.
                IconButton(icon: CloseIcon(), width: 28, height: 28, action: remove)
                    .help("Delete \(category.name)")
                    .opacity(showControls && !sorting ? 1 : 0)
                    .allowsHitTesting(!sorting)
                    .accessibilityLabel("Delete \(category.name)")
                    .padding(.leading, -6)
            }
        }
        // The × reaches into the popover's padding, so its glyph lines up with
        // the panel's right edge and doesn't float away from the name.
        .padding(.trailing, canRemove ? -7 : 0)
        .overlay(alignment: .leading) {
            if canRemove {
                // Centred in the gap between the popover's edge and the dot.
                GripIcon()
                    .fill(theme.muted)
                    .frame(width: 10, height: 14)
                    .frame(width: 14, height: 28)
                    .contentShape(Rectangle())
                    .offset(x: -10)
                    .opacity(showControls || lifted ? 1 : 0)
                    .gesture(grip)
                    .cursor(.openHand)
                    .accessibilityHidden(true)
            }
        }
        // The lifted row is one even chip with a soft shadow all around.
        .background {
            RoundedRectangle(cornerRadius: theme.radiusSmall)
                .fill(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: theme.radiusSmall).strokeBorder(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                .padding(EdgeInsets(top: -3, leading: -17, bottom: -3, trailing: 24))
                .opacity(lifted ? 1 : 0)
        }
        .overlay(alignment: .topLeading) {
            if picking { palette(theme: theme) }
        }
        .onHover { hovering = $0 }
    }

    /// Hover-only controls show all the time on a phone.
    private var showControls: Bool {
        #if os(iOS)
            true
        #elseif DEBUG
            hovering || DebugSnapshot.argument("hover") == category.id  // debug screenshots
        #else
            hovering
        #endif
    }

    /// .swatches: the 14 colours in two rows of seven, floating under the dot.
    private func palette(theme: Theme) -> some View {
        let rows = [Array(Palette.allCases.prefix(7)), Array(Palette.allCases.dropFirst(7))]
        return VStack(spacing: 2) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { p in
                        let on = p == category.color
                        let c = p.strong(in: theme)
                        Button {
                            change { $0.color = p }
                            picking = false
                        } label: {
                            Circle().fill(c).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(c, lineWidth: 1.5).padding(-4.5).opacity(on ? 1 : 0))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pointer)
                        .accessibilityLabel(p.rawValue)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .padding(8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusSmall).strokeBorder(theme.line, lineWidth: 1))
        .cssShadow(y: 16, blur: 40, spread: -16, opacity: 0.35, radius: theme.radiusSmall)
        .offset(x: -6, y: 38)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
    }
}

/// Six dots, "grab here to reorder" (Icons.tsx GripIcon, on a 10×14 grid).
struct GripIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 10, sy = rect.height / 14
        var p = Path()
        for y in [2.0, 7, 12] {
            for x in [2.5, 7.5] {
                p.addEllipse(in: CGRect(x: rect.minX + (x - 1.3) * sx, y: rect.minY + (y - 1.3) * sy, width: 2.6 * sx, height: 2.6 * sy))
            }
        }
        return p
    }
}
