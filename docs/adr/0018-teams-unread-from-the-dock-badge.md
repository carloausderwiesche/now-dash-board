# 0018. The Teams unread count is read from its Dock badge through Accessibility

- **Date:** 2026-11-27
- **Status:** Proposed

## Context

The Dashboard should show how many Microsoft Teams messages are unread, so a glance at the day also says whether someone is waiting. Teams has no local API for this on a Mac, and its web and Graph APIs would need a work-account sign-in and an app registration in someone else's tenant. What every Mac does show is the red number on Teams' Dock icon. macOS exposes what apps draw, including that badge, through the **Accessibility** interface (what screen readers use): the Dock's item for Teams has a "status label" holding the badge text. A test with AppleScript in Terminal read it this way.

## Decision

The Mac app reads Teams' Dock badge through the Accessibility interface and shows it in a "Teams" box on the Dashboard ([the section style](0017-mac-dashboard.md)).

- It looks every 5 seconds, off the main thread, **only while the box is on screen**.
- The text is read by a pure, tested function: nothing or `0` is nothing unread, `3` is three, `99+` is at least 99, and a dot or any other text means "unread, count unknown".
- The box tells apart what it knows: a count, nothing unread, **Teams isn't running** and Teams has no Dock icon (both "no reading", never shown as zero), and **not allowed**.
- **Permission is the person's own act.** macOS only lets an app use Accessibility after it is allowed in System Settings → Privacy & Security → Accessibility. The app never asks on its own: when it isn't allowed the box says so and has an "Allow access" button (which shows macOS's own prompt) and an "Open Settings" button.
- It reads only the badge text of one Dock item. It reads nothing from Teams itself, no message text and no names, and sends nothing anywhere.

## Alternatives considered

- **The Microsoft Graph API:** exact and official, but it needs a work-account sign-in, a registered app and an admin's consent in a company tenant; far more than the glance this is for.
- **Teams' own files or logs:** not a stable or supported place to read an unread count.
- **Notifications:** only fires when something arrives, doesn't hold a current number, and needs another permission.
- **No Teams box:** simplest, but it was an original requirement.

## Consequences

- **Fragile on purpose-built terms.** The Dock's internal structure and the badge text are not a public contract: a macOS update, a Teams update (it already has two bundle ids: classic and the new Teams) or a changed badge style (a dot with no number) can break or blur the reading. The parser says "unknown" instead of guessing, and the box shows "no reading" rather than a wrong number.
- **A Dock that doesn't answer is not "zero".** An error while reading (the Dock busy or restarting) keeps what the box showed before, each question to the Dock times out after one second, and only the item titled "Microsoft Teams" or "Teams" counts.
- **Needs a permission the person grants by hand.** Without it the box says so, and the rest of the app is unaffected. The permission is tied to the app's code signature: a debug build signed ad hoc loses it on every rebuild and must be allowed again.
- **A privacy-relevant permission.** Accessibility lets an app read the screen of other apps. The app only asks the Dock about one icon, but the permission itself is broad, so the person decides, and can withdraw it any time in System Settings.
- The app is not sandboxed ([ADR 0009](0009-mac-app-without-sandbox.md)), which Accessibility needs; a sandboxed app could not do this.
- Revisit if Teams or macOS stop showing the badge this way, or if a calendar or chat box would read the same Teams data in a better way.
