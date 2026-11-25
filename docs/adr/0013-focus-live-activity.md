# 0013. The focus card as a Live Activity

- **Date:** 2026-11-25
- **Status:** Accepted

## Context

The focus card is the one thing you're doing now, but on the iPhone it's only visible inside the app. A glance at the Lock Screen should be enough to remember it. iOS shows "what's happening now" on the Lock Screen and in the Dynamic Island through Live Activities, which need a widget extension (a second target) to draw them.

## Decision

While a Today card is focused, the iPhone app runs a Live Activity for it: the focus card in ink with its category dot, NOW, the title, the checklist count and a timer counting up from when the focus started. The app starts, updates and ends it whenever the focused card changes (`FocusLive.swift`); the new `NowboardWidgets` extension only draws it (`Shared/FocusBanner.swift`, shared with the app). Private tasks show as "Private task", since anyone can read the Lock Screen. The demo board never starts one.

## Alternatives considered

- **A Lock Screen widget (WidgetKit timeline):** needs the task folder from inside the extension (an App Group and shared folder access) and refreshes on the system's schedule, not when the focus changes.
- **A local notification:** gets cleared, and can't stay up to date or show a running timer.

## Consequences

- The project has a second iOS target, signed with the same team, and the iOS app embeds it (`project.yml`).
- The activity only changes while the app runs: focusing a card on the Mac shows on the iPhone's Lock Screen the next time the iPhone app reads the folder. Live Activities also end on their own after 8 hours.
- Buttons on the banner (mark done, pause) would need App Intents; revisit if they're missed.
