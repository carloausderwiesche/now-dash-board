// More icons from src/components/Icons.tsx, drawn on the same 24×24 grid
// (stroke widths are on that grid too), and the muted icon button they sit in.

import SwiftUI

/// `M4 7h16M10 7V4.5h4V7M6.5 7l1 12.5h9l1-12.5M10 11v5M14 11v5` (TrashIcon).
struct TrashIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(4, 7)); p.addLine(to: pt(20, 7))
        p.move(to: pt(10, 7)); p.addLine(to: pt(10, 4.5)); p.addLine(to: pt(14, 4.5)); p.addLine(to: pt(14, 7))
        p.move(to: pt(6.5, 7)); p.addLine(to: pt(7.5, 19.5)); p.addLine(to: pt(16.5, 19.5)); p.addLine(to: pt(17.5, 7))
        p.move(to: pt(10, 11)); p.addLine(to: pt(10, 16))
        p.move(to: pt(14, 11)); p.addLine(to: pt(14, 16))
        return p
    }
}

/// `M6 6l12 12M18 6L6 18` (CloseIcon).
struct CloseIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 6 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 18 * s, y: 18 * s))
        p.move(to: CGPoint(x: 18 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 6 * s, y: 18 * s))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// .iconbtn: an icon in the muted colour that turns ink on hover (0.2s),
/// with a hand cursor and an optional tooltip.
struct IconButton<Icon: Shape>: View {
    @Environment(BoardStore.self) private var store
    let icon: Icon
    var size: CGFloat = 16
    var stroke: CGFloat = 1.8
    var width: CGFloat = 36
    var height: CGFloat = 44
    var tip: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let theme = store.theme
        Button(action: action) {
            icon
                .stroke(hovering ? theme.ink : theme.muted,
                        style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
        .modifier(OptionalTip(text: tip))
    }
}

private struct OptionalTip: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.tip(text)
        } else {
            content
        }
    }
}
