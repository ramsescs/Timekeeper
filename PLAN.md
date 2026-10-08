# Timekeeper — MVP plan

## Context
Build a personal macOS menu bar app for tracking work time per activity and enforcing breaks, inspired by Cronometer (`inspo/`: a dark popover with tabs Tracking/Statistics/Settings, a "Next break at HH:MM" line, today's Work/Break tiles, and a full-screen blurred break overlay with a message, progress bar, countdown and a small "Skip"). Greenfield repo: only `inspo/` exists, and it is not a git repo yet.

**Decisions made with the user:**
- Only one activity runs at a time. Starting B pauses A. Today's work time = sum of all activities, with no double counting.
- Skipping a break: the break never happened, the seconds spent on the overlay count as work, and the next break comes after a **full** new block.

**Defaults I chose (easy to flip):**
- A real rest resets the block. If the tracker was idle (paused or asleep) for ≥ the break length, the block resets to 0 when work resumes. Otherwise, after 40 min of evening work, the next morning's break would fire 10 min in.
- Deleting an activity **archives** it. It is hidden from Today, but its history stays in Stats, so the work total always equals the sum of the rows.

**Toolchain constraint:** no Xcode, only Command Line Tools (Swift 6.3, macOS 26.5). The CLT ships `Testing.framework` (Swift Testing) and the Observation macros plugin (`@Observable`). `Testing.framework` is not on the default search path, so run tests with `./scripts/test.sh`, which adds those paths. Plain `swift test` fails with "no such module 'Testing'". So we use a **Swift Package** plus a `scripts/bundle.sh` that wraps the binary into `Timekeeper.app` (`LSUIElement` = menu bar only, no Dock icon). No `.xcodeproj`, SwiftData or XCTest. Persistence is a plain JSON file.

## Behavior spec (MVP)
- **Menu bar item** (`MenuBarExtra`, `.window` style): an SF Symbol plus today's work total (`1h 25m`) while an activity runs, the icon alone when idle.
- **Popover, 3 tabs** (bottom tab bar like the inspo):
  1. **Today**: tiles for Work today / Break today, a "Next break at 21:33" line, and Pause. Below that, a list of activities, each with a play/pause button and its time today. The running one is highlighted. An inline "+ New activity" field (name only, auto color). Rename and delete via context menu. Quit button.
  2. **Stats**: Week / Month / Year segmented control (current calendar period). One row per activity: name, total, proportional bar. Grand total at the top.
  3. **Settings**: session block length (min, default 50), break length (min, default 10), break message text. Stored in `UserDefaults`.
- **Break flow:**
  - Block time = work seconds accumulated since the last break or skip. It advances only while an activity runs, so Pause keeps it as is and does not reset it.
  - When block ≥ block length: close the work entry at `t0`, open a break entry, and show the overlay on **every screen**. The overlay is blurred and shows the message, a progress bar and an `MM:SS` countdown, with a small Skip button.
  - **Countdown reaches 0**: the overlay switches to a "Back to work" button. Break time keeps counting until it is clicked. This avoids logging phantom work if you walked away. Click: close the break entry, resume the same activity, reset the block to 0.
  - **Skip**: delete the break entry, reopen work for the same activity starting at `t0`, reset the block to 0.
- **Sleep/lock** (`NSWorkspace.willSleepNotification` / `screensDidSleep`): auto-pause the running activity so nights aren't counted. If this happens **during a break**, close the break entry at the sleep time, dismiss the overlay and go idle, so the night isn't logged as break time either.
- **Quit/crash:** on quit, close open entries. A `lastSeen` heartbeat is saved every 30 s. On launch, any entry left open is closed at `lastSeen`.

## Architecture
Pure logic lives in a testable library. The app target is thin UI and AppKit glue.

```
Package.swift                         # tools 6.0, macOS 14+, targets below
Sources/TimekeeperCore/               # no AppKit/SwiftUI — fully unit-testable
  Models.swift      Activity{id,name,colorHex}, TimeEntry{id,kind:.work/.break,activityID?,start,end?}
  Tracker.swift     struct state machine; every mutating fn takes `now: Date`
                    start(activity:), pause(), beginBreak(), skipBreak(), endBreak(), tick() -> event
                    holds runningActivityID, phase(.idle/.working/.onBreak), blockAccumulated, breakStartedAt
  Stats.swift       total(kind:, activity:, in: DateInterval) — clips entries to the range (midnight-safe);
                    DateInterval helpers for today/week/month/year via Calendar
  Store.swift       Codable snapshot {activities, entries, tracker, lastSeen} ⇄
                    ~/Library/Application Support/Timekeeper/data.json (atomic write); recover() closes open entries
Sources/Timekeeper/                   # app
  TimekeeperApp.swift   @main, MenuBarExtra + AppDelegate (sleep/wake + terminate hooks)
  AppModel.swift        @MainActor @Observable; owns Tracker+Store; 1 s Timer → tick(), triggers overlay, saves
  Views/PopoverView.swift (tab bar) · TodayView.swift · StatsView.swift · SettingsView.swift
  Break/BreakOverlayController.swift  one borderless NSWindow per NSScreen, level .screenSaver,
                                       canJoinAllSpaces+fullScreenAuxiliary, NSVisualEffectView blur
  Break/BreakView.swift               SwiftUI content (message, progress, countdown, Skip / Back to work)
Tests/TimekeeperCoreTests/            # Swift Testing
  TrackerTests.swift  StatsTests.swift  StoreTests.swift
Resources/Info.plist                  # LSUIElement=YES, bundle id, version
scripts/bundle.sh                     # swift build -c release → build/Timekeeper.app, ad-hoc codesign
```

Time is never accumulated by counting ticks. Totals always come from entry timestamps (`end ?? now` − `start`), so a missed tick or a sleeping timer can't cause drift. The 1 s tick only refreshes the UI and checks the block threshold.

## Implementation steps
0. On approval: write this plan to `PLAN.md` in the repo and **stop** until told to implement.
1. `git init`, `.gitignore` (`.build/`, `build/`, `.DS_Store`). Commits stage files by name.
2. `Package.swift` and the `TimekeeperCore` models, tracker and stats, **with tests first** (`./scripts/test.sh`).
3. `Store` and recovery, with a round-trip test.
4. App shell: `MenuBarExtra`, `AppModel`, Today tab. Bundle script, launch, and manually check start/switch/pause.
5. Break overlay controller and view. Wire up block threshold, skip and end-break.
6. Stats tab, then Settings tab.
7. Sleep auto-pause, quit/crash recovery, heartbeat.

## Verification
- `./scripts/test.sh`: tracker scenarios (switch activity pauses the other; block threshold fires at the exact second; skip turns the break back into work and resets the block; end-break resumes the same activity; a short pause keeps block time but an idle gap ≥ break length resets it; sleep during a break closes the break at the sleep time), stats (an entry spanning midnight splits correctly across days; week/month/year sums), and the store round-trip plus recovery of open entries.
- `./scripts/bundle.sh && open build/Timekeeper.app`, then by hand:
  - Set the block to 1 min and the break to 1 min in Settings, then start an activity. The overlay appears on all screens after 1 min.
  - Skip: work keeps counting and "Next break" moves about 1 min ahead.
  - Let the break finish, then click "Back to work": the Break tile increases and the same activity resumes.
  - Switch between two activities. The Today work total equals the sum of the rows.
  - Quit and relaunch: the totals persist.

## Deferred (mention, don't build)
Idle detection, launch at login (`SMAppService`), streaks, app-usage tracking, charts in Stats, colors/emoji per activity, editing past entries, CSV export, notifications before a break, postpone/snooze.
