// Small helpers that do what the Tauri app's CSS does, so views can say
// `.cssShadow(y: 14, blur: 30, spread: -16, opacity: 0.35)` and get the same
// result as `box-shadow: 0 14px 30px -16px rgba(0,0,0,.35)`.

import SwiftUI

#if os(macOS)
    import AppKit
#endif

extension View {
    /// CSS `box-shadow` for a rounded card. SwiftUI's own `.shadow` has no
    /// *spread*; CSS's negative spread shrinks the shadow before blurring, so
    /// only a soft line peeks out under the card instead of a dark halo. Here
    /// the shadow is a blurred copy of the card's shape, shrunk by the spread.
    /// CSS blur is about twice SwiftUI's blur radius.
    func cssShadow(y: CGFloat, blur: CGFloat, spread: CGFloat, opacity: Double, radius: CGFloat, visible: Bool = true) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.black.opacity(opacity))
                .padding(-spread)
                .offset(y: y)
                .blur(radius: blur / 2)
                .opacity(visible ? 1 : 0)
        }
    }

    /// The Tauri app's `data-tip`: on hover, a small ink label right under the
    /// element, sliding down 3pt as it fades in (0.12s). Mac only; on iOS it
    /// stays out of the way (there's no hover).
    func tip(_ text: String, inverted: Bool = false) -> some View {
        modifier(Tip(text: text, inverted: inverted))
    }

    /// The pointer shape while over this view (Mac): `.pointingHand` for
    /// buttons, `.openHand` for cards you can drag.
    func cursor(_ kind: CursorKind) -> some View {
        modifier(CursorModifier(kind: kind))
    }
}

enum CursorKind {
    case pointingHand, openHand
}

private struct Tip: ViewModifier {
    @Environment(BoardStore.self) private var store
    let text: String
    let inverted: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
            let theme = store.theme
            content
                .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
                .overlay(alignment: .bottom) {
                    Text(text)
                        .font(theme.font(11, .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(inverted ? theme.ink : theme.bg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(inverted ? theme.bg : theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                        .alignmentGuide(.bottom) { d in d[.top] - 2 }  // top: 100% + 2px
                        .offset(y: hovering ? 0 : -3)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .zIndex(hovering ? 50 : 0)
        #else
            content
        #endif
    }
}

private struct CursorModifier: ViewModifier {
    let kind: CursorKind

    func body(content: Content) -> some View {
        #if os(macOS)
            content.onHover { inside in
                // AppKit keeps a stack of cursors: push ours on enter, pop it on leave.
                if inside {
                    (kind == .pointingHand ? NSCursor.pointingHand : NSCursor.openHand).push()
                } else {
                    NSCursor.pop()
                }
            }
        #else
            content
        #endif
    }
}
