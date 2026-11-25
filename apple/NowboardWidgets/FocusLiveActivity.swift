// The widget extension: only the focus Live Activity (ADR 0013). The app
// starts, updates and ends it (FocusLive.swift); this draws it.

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NowboardWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            FocusBanner(focus: context.state.focus, since: context.attributes.since)
                .activityBackgroundTint(FocusBanner.ink)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let focus = context.state.focus
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        FocusDot(color: focus.color)
                        Text("NOW").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusTimer(since: context.attributes.since)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: 64)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                        if focus.total > 0 {
                            Text("\(focus.done) / \(focus.total)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                FocusDot(color: focus.color, size: 10)
            } compactTrailing: {
                FocusTimer(since: context.attributes.since)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(maxWidth: 44)
            } minimal: {
                FocusDot(color: focus.color, size: 10)
            }
        }
    }
}
