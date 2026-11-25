// The focus card on the Lock Screen and in the Dynamic Island (a Live
// Activity, ADR 0013). Built into the app and the widget extension: the app
// starts and updates it, the extension draws it. The views take plain values,
// so the app can also render them for a snapshot.

import SwiftUI

#if os(iOS)
    import ActivityKit

    struct FocusAttributes: ActivityAttributes {
        /// The task's file name: focusing another task ends this activity.
        var id: String
        /// When the focus started (when the activity did), for the timer.
        var since: Date

        struct ContentState: Codable, Hashable {
            var focus: FocusInfo
        }
    }
#endif

/// What the banner shows about the focused task.
struct FocusInfo: Codable, Hashable, Sendable {
    var title: String
    var category: String
    /// The category's colour for a dark background.
    var color: Color.Resolved
    var done: Int
    var total: Int
}

/// The Lock Screen banner: the focus card in ink, like on the board.
struct FocusBanner: View {
    let focus: FocusInfo
    let since: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FocusDot(color: focus.color)
                Text("NOW")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 8)
                FocusTimer(since: since)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(focus.title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .lineLimit(2)
            if focus.total > 0 {
                Text("\(focus.done) / \(focus.total)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The board's ink (Braun theme), behind the banner.
    static let ink = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1A / 255)
}

struct FocusDot: View {
    let color: Color.Resolved
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(Color(color)).frame(width: size, height: size)
    }
}

/// Minutes and seconds since the focus started, counting up on its own.
struct FocusTimer: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}