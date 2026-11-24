# 0005. The vault syncs through iCloud Drive; the operating system does the syncing

- **Date:** 2026-11-24
- **Status:** Accepted

## Context

Nestor wants Nowboard on his Mac and his iPhone, editing the same task files in his Obsidian vault. Changes should travel on their own: no app (Obsidian or Nowboard) has to be open on the other device.

Today the vault lives in `~/MEGA/Personal/Cosas mías/test`, MEGA backs the folder up, and Obsidian's Self-hosted LiveSync plugin syncs it between devices. LiveSync only syncs while Obsidian is running, and an iPhone app can't open a MEGA folder in place: MEGA's iOS app doesn't share its files with other apps.

An inventory of scripts and configs on the Mac, made before this decision, found nothing that reads the vault from another machine. Open WebUI on the home server only receives files that a script on the Mac uploads. So an Apple-only sync is possible.

## Decision

The vault moves to an **Obsidian iCloud vault** (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/<vault>`), and iCloud Drive syncs it. LiveSync is switched off for this vault and must never run alongside iCloud on it. Nowboard doesn't sync anything itself: it reads and writes files, and the operating system moves them in the background.

**When:** only after the SwiftUI macOS app has replaced the Tauri app ([ADR 0006](0006-native-swiftui-app.md)). Until then the vault stays on MEGA and LiveSync, where the Tauri app works today, so the Tauri app never needs to learn iCloud's quirks. Nestor moves the vault by hand, following a checklist (`docs/migrate-to-icloud.md`, written when the move gets close). No code or test touches the real vault.

## Alternatives considered

- **Keep LiveSync:** only syncs while Obsidian runs on both ends, so a task added on the phone doesn't reach the Mac until Obsidian opens there. Nowboard would have to talk to CouchDB to avoid that.
- **LiveSync Bridge plus a small API on Hetzner:** works without Obsidian, but adds a server, a database and an API that all have to stay up. Every edit needs a network connection, and the apps need sync code.
- **MEGA:** doesn't expose its files to other iOS apps in place, so an iPhone app can't read or write the vault.

## Consequences

- Sync "just works" with every app closed, on both devices. The iPhone app can use Apple's own file APIs.
- **Apple-only.** Every device that edits the vault must be a Mac, iPhone or iPad. A Linux or Windows machine couldn't reach it. Together with this decision, that's why [ADR 0006](0006-native-swiftui-app.md) drops the cross-platform Tauri app.
- **Slower sync:** seconds to minutes, not instant. It's checked with a 10-minute test in the migration checklist.
- **Conflicts become duplicate files** (`Buy milk 2.md`) instead of merges. The spec treats them as ordinary tasks; the Swift app flags likely duplicates on the card and never deletes them on its own.
- **Files may not be downloaded yet.** The app has to skip or download them instead of failing. On the Mac, the vault folder needs "Keep Downloaded" (Optimize Mac Storage must not evict it).
- **Privacy:** the vault (with `Private/` and finances) sits in iCloud. Turning on Advanced Data Protection is recommended so Apple can't read it.
- **Backups and scripts:** the restic backup only covers `~/MEGA`, so the new path has to be added, as do the 14 scripts and configs found in the inventory.
- We'd revisit this if a non-Apple device has to edit the vault, or if iCloud sync proves too slow or unreliable in daily use.
