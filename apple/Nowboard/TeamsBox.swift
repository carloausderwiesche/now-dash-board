// The Teams box on the Dashboard: how many messages are unread, from the
// Dock badge. A section like the others (DashboardSection): the number big,
// a few words next to it, muted when there is nothing to see.

#if os(macOS)
    import NowboardKit
    import SwiftUI

    struct TeamsBox: View {
        @Environment(BoardStore.self) private var store
        @Environment(TeamsUnreadModel.self) private var model

        var body: some View {
            let theme = store.theme
            DashboardSection(title: "Teams") {
                if let display = model.display {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(display.headline)
                            .font(theme.font(display.headline.count > 3 ? 28 : 36, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(display.muted ? theme.muted : theme.ink)
                        Text(display.detail)
                            .font(theme.font(14))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    if display.needsPermission {
                        HStack(spacing: 10) {
                            Button { model.requestAccess() } label: {
                                Text("Allow access")
                                    .font(theme.font(14, .semibold))
                                    .foregroundStyle(theme.bg)
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(theme.ink, in: RoundedRectangle(cornerRadius: theme.radiusSmall + 2))
                            }
                            .buttonStyle(.pointer)
                            Button { model.openSettings() } label: {
                                Text("Open Settings")
                                    .font(theme.font(14, .semibold))
                                    .foregroundStyle(theme.muted)
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                            }
                            .buttonStyle(.pointer)
                        }
                    }
                } else {
                    // Not looked yet: a quiet placeholder for a moment, not a wrong number.
                    Text("…").font(theme.font(36, .semibold)).foregroundStyle(theme.muted)
                }
            }
            // Looks now and every few seconds while the box is on screen; stops when it leaves.
            .task {
                #if DEBUG
                    if model.isDemo { model.applyDebugArguments(); return }
                #endif
                await model.poll()
            }
        }
    }
#endif
