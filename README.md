# Timekeeper

A small macOS menu bar app that tracks your work time per activity and makes you take breaks.

Start an activity, and Timekeeper counts your time. After each work block (50 min by default), a blurred full-screen break overlay covers every display until the break is over. You can see your totals for today, the week, the month and the year, broken down by activity.

## Features

- **Menu bar timer.** A small robot icon shows today's work total while an activity runs.
- **Activities.** Only one activity runs at a time. Starting one pauses the other, so time is never counted twice. You can rename activities, archive them (their history stays in Stats) or delete them for good.
- **Enforced breaks.** After each work block, a break screen appears on every display. It shows your message, a progress bar and a countdown. From there you can:
  - **Snooze** for a set time, or pick a custom number of minutes.
  - **Skip** the break. The time you spent on the overlay counts as work, and the next break comes after a full block.
  - Start a **long break** instead.
  - **Pause Timekeeper** entirely.
  
  When the countdown ends, the screen waits for **Back to work**, so time you spend away from the desk is not logged as work.
- **Long breaks.** Optional: a longer break every N sessions, like Pomodoro.
- **Stats.** Week, month and year views with a stacked bar chart per activity, plus totals per activity.
- **Smart pausing.** Tracking pauses automatically when the Mac sleeps or the screen locks. Stepping away for at least the break length starts a fresh block.
- **Crash-safe.** A heartbeat is saved every 30 s. On the next launch, any entries left open are closed at the last time the app was seen running.
- **Phone notification (optional).** Get a push on your phone through [ntfy](https://ntfy.sh) when a break ends.
- **Launch at login.**

## Requirements

- macOS 14 or later
- Swift 6 toolchain. Xcode **not** required: the Command Line Tools are enough.

## Build & run

```bash
./scripts/bundle.sh          # release build → build/Timekeeper.app (ad-hoc signed)
open build/Timekeeper.app
```

To keep the app, copy `build/Timekeeper.app` into `/Applications`. It runs in the menu bar only and has no Dock icon.

## Tests

```bash
./scripts/test.sh
```

The tests use Swift Testing. With only the Command Line Tools installed, `Testing.framework` is not on the default search path, so plain `swift test` fails with "no such module 'Testing'". The script adds the needed paths for you.

## How it works

```
Sources/TimekeeperCore/   Pure logic, no AppKit/SwiftUI, fully unit-tested
  Models.swift            Activity, TimeEntry (work/break, start, end?)
  Tracker.swift           State machine: start / pause / break / skip / snooze; every call takes `now`
  Stats.swift             Totals per kind/activity over a DateInterval (midnight-safe clipping)
  Store.swift             JSON snapshot + crash recovery
Sources/Timekeeper/       Thin UI + AppKit glue
  TimekeeperApp.swift     MenuBarExtra, sleep/wake + quit hooks
  AppModel.swift          Owns Tracker + Store, 1 s tick, triggers the overlay
  Views/                  Today, Stats (+ chart), Settings tabs
  Break/                  One borderless blurred window per screen + break UI
```

Totals are never built up by counting ticks. They always come from entry timestamps (`end ?? now − start`), so a missed tick or a sleeping timer cannot cause drift. The 1-second tick only refreshes the UI and checks whether the block is over.

Your data lives in `~/Library/Application Support/Timekeeper/data.json`. Settings are stored in `UserDefaults`.

## Privacy

Everything stays on your Mac. The only network request is the optional ntfy notification, sent to the topic you choose. ntfy topics are public, so Timekeeper creates a long random topic name by default.
