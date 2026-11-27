# 0019. Sites are blocked during a focus session through the hosts file, by a root helper

- **Date:** 2026-11-27
- **Status:** Proposed

## Context

A focus session should keep the person away from the sites that pull them out of it (YouTube, social networks). The most direct way on a Mac, one that works in every browser without an extension, is the hosts file: a line like `127.0.0.1 youtube.com` in `/etc/hosts` sends that name to the Mac itself, where nothing answers. The file belongs to root, and Nowboard is an ordinary app, so changing it needs a privileged helper.

## Decision

- **A helper program, installed with `SMAppService`.** The app contains a small program (`NowboardHelper`) and its launchd description. The person approves it once in System Settings → General → Login Items & Extensions; macOS then runs it as root. The app talks to it over XPC with two calls that matter: `block(domains, until)` and `unblock()`.
- **The helper only edits its own marked block** in `/etc/hosts` (`# >>> nowboard focus block` … `# <<< nowboard focus block`), flushes the name cache, and removes the block when the time is up. Every other line stays exactly as it is, line endings included (this is pure, heavily tested text code in `NowboardKit`, `HostsBlock`).
- **It holds its own deadline.** The end time is kept in a file only root can write, and checked every 10 seconds, so a closed or crashed app can't leave the sites blocked. A block is never longer than four hours, whatever the app asks. When the helper starts (at login, or after a crash) it removes a block that has run out or has no deadline.
- **It trusts nobody.**
  - It only answers a caller whose code signature is the Nowboard app signed by the same developer team as the helper (`setCodeSigningRequirement`). The app does the same check on the helper. A helper with no team signature (an ad-hoc build) answers nobody.
  - It checks every site name itself: plain ASCII host names only, no spaces, line breaks, `#` or addresses, at most 500 of them. The names are only ever written as `127.0.0.1 <name>` and `::1 <name>` lines, and no command receives them.
  - The only commands it runs are `dscacheutil -flushcache` and `killall -HUP mDNSResponder`, with fixed arguments.
- **Some names are never blocked**: the Mac's own (`localhost`, `*.local`, reverse-lookup names) and Apple's services (`apple.com`, `icloud.com`, certificate and update hosts), whoever asks, because blocking those would only break the Mac for a few hours. Settings refuses them with a reason. Calls to the helper time out after 10 seconds on the app's side, and the commands the helper runs after a change are limited to 5 seconds, so a stuck step can't freeze the deadline check.
- **What is blocked is the person's list** (Settings → Blocked during focus, with YouTube, Instagram, X, Reddit, Facebook and TikTok as the default). Each entry stands for all the names the site uses (`youtube.com`, `www.`, `m.`, `youtu.be`…). Blocking can be switched off in the Focus section, and it is on by default.
- **Nothing happens without the setup.** The app never writes the hosts file itself and never calls the helper until the person has set it up and approved it; until then the Focus section says so and offers the setup.

## Alternatives considered

- **A browser extension:** per browser, easy to switch off in the middle of the session, and it needs its own distribution.
- **A network or DNS filter (a local DNS proxy, a configuration profile):** stronger and also covers apps, but far heavier and invasive: it changes the Mac's network setup. Not for this.
- **`osascript … with administrator privileges` on each session:** no helper to maintain, but a password prompt at every session start and end, and nothing runs if the app is gone when the time is up.
- **Blocking in the app only (a full-screen overlay):** doesn't stop the sites from working.

## Consequences

- **It can be bypassed, and that is accepted.** Anything that doesn't use the system's resolver ignores the hosts file: a browser with its own **Secure DNS (DNS over HTTPS)** setting turned to a custom provider, **iCloud Private Relay** (for Safari traffic), a VPN with its own DNS, or an already-open page whose connection or DNS answer is still cached (reload it). This Mac uses its router's DNS and has Safari, Chrome, Arc and Dia installed; Chromium browsers only switch to DoH on their own when the system DNS is a provider they know. This is a speed bump for habit, not a lock against a determined person.
- **A root helper is a real attack surface**, so it is kept small: two calls, strict checks and a fixed block of lines. The caller check relies on code signing.
- **It needs a signed app.** The caller checks use the developer team in the code signature: the helper only answers an app signed by its own team, and the app only talks to a helper signed by its own team. The Mac app and the helper are signed with Carlo's Personal Team (`JZLT94DZPK` in `project.yml`, with the "Apple Development" certificate); anyone building with another Apple ID changes that one line (twice). An ad-hoc build has no team: the helper then refuses every caller and the app doesn't call it, so blocking stays off. Whether macOS lets a free Personal Team register a launch daemon with `SMAppService` is not verified yet: that is what the first live test shows.
- **/etc/hosts is shared.** Hand-written entries are never touched, but another program that edits the file at the same moment could conflict. Writes are atomic (a temporary file and a rename) and the block is replaced, not appended to, so repeated blocks never pile up.
- Revisit if the bypasses turn out to matter in practice (then a DNS-level filter is the next step), or if the helper can't be signed.
