import AppKit
import Observation
import TimekeeperCore

enum SettingsKey {
    static let blockMinutes = "blockMinutes"
    static let breakMinutes = "breakMinutes"
    static let breakMessage = "breakMessage"
    static let longBreakEnabled = "longBreakEnabled"
    static let longBreakEvery = "longBreakEvery"
    static let longBreakMinutes = "longBreakMinutes"
    static let snoozeMinutes = "snoozeMinutes"
    static let phoneNotify = "phoneNotify"
    static let ntfyTopic = "ntfyTopic"

    static let defaultBlockMinutes = 50
    static let defaultBreakMinutes = 10
    static let defaultBreakMessage = "Time for a break — stand up, stretch and rest your eyes"
    static let defaultLongBreakEnabled = true
    static let defaultLongBreakEvery = 4
    static let defaultLongBreakMinutes = 20
    static let defaultSnoozeMinutes = 5
    static let defaultPhoneNotify = false
}

/// Owns the tracker, persists it, and drives the 1 s tick that refreshes the UI and triggers breaks.
@MainActor @Observable
final class AppModel {
    private(set) var tracker = Tracker()
    private(set) var now = Date()

    @ObservationIgnored private let store = Store(url: Store.defaultURL)
    @ObservationIgnored private let overlay = BreakOverlayController()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSaved = Date.distantPast
    /// Start of the break we already sent the "break's over" push for, so it goes out once per break.
    @ObservationIgnored private var notifiedBreakStart: Date?

    var blockLength: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: SettingsKey.blockMinutes) * 60) }
    var breakLength: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: SettingsKey.breakMinutes) * 60) }
    var snoozeMinutes: Int { UserDefaults.standard.integer(forKey: SettingsKey.snoozeMinutes) }
    var longBreakLength: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: SettingsKey.longBreakMinutes) * 60) }
    /// Sessions per long break, or nil when long breaks are off.
    var longBreakEvery: Int? {
        UserDefaults.standard.bool(forKey: SettingsKey.longBreakEnabled) ? UserDefaults.standard.integer(forKey: SettingsKey.longBreakEvery) : nil
    }
    /// Length of the break in progress (long or short).
    var currentBreakLength: TimeInterval { tracker.isLongBreak ? longBreakLength : breakLength }
    var nextBreakIsLong: Bool { tracker.nextBreakIsLong(longBreakEvery: longBreakEvery) }
    var breakMessage: String { UserDefaults.standard.string(forKey: SettingsKey.breakMessage) ?? SettingsKey.defaultBreakMessage }

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.blockMinutes: SettingsKey.defaultBlockMinutes,
            SettingsKey.breakMinutes: SettingsKey.defaultBreakMinutes,
            SettingsKey.breakMessage: SettingsKey.defaultBreakMessage,
            SettingsKey.longBreakEnabled: SettingsKey.defaultLongBreakEnabled,
            SettingsKey.longBreakEvery: SettingsKey.defaultLongBreakEvery,
            SettingsKey.longBreakMinutes: SettingsKey.defaultLongBreakMinutes,
            SettingsKey.snoozeMinutes: SettingsKey.defaultSnoozeMinutes,
            SettingsKey.phoneNotify: SettingsKey.defaultPhoneNotify,
        ])
        // Random per install, so generate once and persist (register(defaults:) would re-roll every launch).
        if UserDefaults.standard.string(forKey: SettingsKey.ntfyTopic) == nil {
            UserDefaults.standard.set(PhoneNotifier.randomTopic(), forKey: SettingsKey.ntfyTopic)
        }
        do {
            if let snapshot = try store.load() {
                tracker = snapshot.tracker
                tracker.recover(lastSeen: snapshot.lastSeen)
            }
        } catch {
            NSLog("Timekeeper: could not read data file, backing it up: \(error)")
            store.backUpCorruptFile()
        }
        save()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Derived

    var today: DateInterval { Calendar.current.periodInterval(.day, containing: now) }

    func todayTotal(_ kind: EntryKind, activity: UUID? = nil) -> TimeInterval {
        tracker.total(kind: kind, activity: activity, in: today, now: now)
    }

    var nextBreak: Date? { tracker.nextBreak(now: now, blockLength: blockLength) }

    // MARK: Actions

    func toggle(_ id: UUID) {
        if tracker.phase == .working && tracker.runningActivityID == id {
            mutate { $0.pause(now: $1) }
        } else {
            let longBreakLength = longBreakEvery == nil ? nil : self.longBreakLength
            mutate { [breakLength] in $0.start(id, now: $1, breakLength: breakLength, longBreakLength: longBreakLength) }
        }
    }

    func pauseOrResume() {
        switch tracker.phase {
        case .working: mutate { $0.pause(now: $1) }
        case .idle: if let id = tracker.lastActivityID { toggle(id) }
        case .onBreak: break
        }
    }

    /// Start a break right now instead of waiting for the block to finish.
    func takeBreak(long: Bool = false) {
        mutate { [longBreakEvery] in $0.beginBreak(now: $1, longBreakEvery: longBreakEvery, forceLong: long) }
        if tracker.phase == .onBreak { overlay.show(model: self) }
    }

    func resetBlock() {
        mutate { $0.resetBlock(now: $1) }
    }

    /// Postpone the break by `minutes` (defaults to the snooze length from Settings).
    func snoozeBreak(minutes: Int? = nil) {
        overlay.hide()
        let snooze = TimeInterval((minutes ?? snoozeMinutes) * 60)
        mutate { [blockLength] in $0.snoozeBreak(now: $1, blockLength: blockLength, snooze: snooze) }
    }

    func skipBreak() {
        overlay.hide()
        mutate { $0.skipBreak(now: $1) }
    }

    func endBreak() {
        overlay.hide()
        mutate { $0.endBreak(now: $1) }
    }

    func addActivity(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        mutate { t, _ in t.addActivity(name: name) }
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        mutate { t, _ in t.rename(id, to: name) }
    }

    func archive(_ id: UUID) {
        mutate { $0.archive(id, now: $1) }
    }

    func deletePermanently(_ id: UUID) {
        mutate { $0.deleteActivity(id, now: $1) }
    }

    func startLongBreak() {
        mutate { t, _ in t.upgradeToLongBreak() }
        notifiedBreakStart = nil  // the short break's "over" push may have gone out; the long one gets its own
    }

    /// End the break now and stop tracking until the user resumes.
    func pauseFromBreak() {
        overlay.hide()
        mutate { $0.pause(now: $1) }
    }

    /// Sleep / lock: stop counting work, and end a break at this moment so the night isn't logged.
    func handleSleep() {
        overlay.hide()
        mutate { $0.pause(now: $1) }
    }

    func shutdown() {
        mutate { $0.pause(now: $1) }
    }

    // MARK: Internals

    private func mutate(_ change: (inout Tracker, Date) -> Void) {
        now = Date()
        change(&tracker, now)
        save()
    }

    private func tick() {
        now = Date()
        if tracker.shouldBreak(now: now, blockLength: blockLength) {
            tracker.beginBreak(now: now, longBreakEvery: longBreakEvery)
            overlay.show(model: self)
            save()
        } else if now.timeIntervalSince(lastSaved) >= 30 {
            save()
        }
        notifyIfBreakOver()
    }

    private func notifyIfBreakOver() {
        guard tracker.phase == .onBreak, let start = tracker.breakStartedAt, notifiedBreakStart != start,
              tracker.breakElapsed(now: now) >= currentBreakLength else { return }
        notifiedBreakStart = start
        guard UserDefaults.standard.bool(forKey: SettingsKey.phoneNotify),
              let topic = UserDefaults.standard.string(forKey: SettingsKey.ntfyTopic) else { return }
        let title = tracker.isLongBreak ? "Long break's over" : "Break's over"
        Task {
            do {
                try await PhoneNotifier.send(topic: topic, title: title, message: "Back to work!", tags: "muscle")
            } catch {
                NSLog("Timekeeper: phone notification failed: \(error)")
            }
        }
    }

    private func save() {
        do {
            try store.save(Snapshot(tracker: tracker, lastSeen: now))
            lastSaved = now
        } catch {
            NSLog("Timekeeper: save failed: \(error)")
        }
    }
}
