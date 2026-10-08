import Foundation
import Testing
@testable import TimekeeperCore

let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }
let everything = DateInterval(start: at(-1), end: at(1_000_000))

let blockLength: TimeInterval = 3000
let breakLength: TimeInterval = 600

private func makeTracker() -> (Tracker, UUID, UUID) {
    var t = Tracker()
    let a = t.addActivity(name: "A")
    let b = t.addActivity(name: "B")
    return (t, a, b)
}

struct TrackerTests {
    @Test func switchingActivityPausesThePreviousOne() {
        var (t, a, b) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.start(b, now: at(100), breakLength: breakLength)

        #expect(t.runningActivityID == b)
        #expect(t.entries.filter { $0.end == nil }.count == 1)
        #expect(t.total(kind: .work, activity: a, in: everything, now: at(300)) == 100)
        #expect(t.total(kind: .work, activity: b, in: everything, now: at(300)) == 200)
        #expect(t.total(kind: .work, in: everything, now: at(300)) == 300)
    }

    @Test func blockThresholdFiresAtTheExactSecondAcrossSwitches() {
        var (t, a, b) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.start(b, now: at(1000), breakLength: breakLength)

        #expect(!t.shouldBreak(now: at(2999), blockLength: blockLength))
        #expect(t.shouldBreak(now: at(3000), blockLength: blockLength))
        #expect(t.nextBreak(now: at(1000), blockLength: blockLength) == at(3000))
    }

    @Test func skipTurnsBreakBackIntoWorkAndStartsAFullBlock() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.beginBreak(now: at(3000))
        t.skipBreak(now: at(3010))

        #expect(t.phase == .working)
        #expect(t.runningActivityID == a)
        #expect(!t.entries.contains { $0.kind == .breakTime })
        #expect(t.total(kind: .work, in: everything, now: at(3010)) == 3010)
        #expect(!t.shouldBreak(now: at(5999), blockLength: blockLength))
        #expect(t.shouldBreak(now: at(6000), blockLength: blockLength))
    }

    @Test func endBreakLogsBreakAndResumesSameActivity() {
        var (t, _, b) = makeTracker()
        t.start(b, now: at(0), breakLength: breakLength)
        t.beginBreak(now: at(3000))
        #expect(t.breakElapsed(now: at(3300)) == 300)
        t.endBreak(now: at(3700))

        #expect(t.phase == .working)
        #expect(t.runningActivityID == b)
        #expect(t.total(kind: .breakTime, in: everything, now: at(4000)) == 700)
        #expect(t.total(kind: .work, in: everything, now: at(4000)) == 3300)
        #expect(t.blockElapsed(now: at(3700)) == 0)
    }

    @Test func shortPauseKeepsBlockButRealRestResetsIt() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.pause(now: at(1000))
        t.start(a, now: at(1300), breakLength: breakLength)
        #expect(t.blockElapsed(now: at(1300)) == 1000)

        t.pause(now: at(1400))
        t.start(a, now: at(2000), breakLength: breakLength)
        #expect(t.blockElapsed(now: at(2000)) == 0)
    }

    @Test func pauseDuringBreakClosesBreakAtThatMoment() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.beginBreak(now: at(3000))
        t.pause(now: at(3100))

        #expect(t.phase == .idle)
        #expect(t.lastActivityID == a)
        #expect(t.total(kind: .breakTime, in: everything, now: at(90_000)) == 100)
    }

    @Test func archivingRunningActivityPausesAndKeepsHistory() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.archive(a, now: at(500))

        #expect(t.phase == .idle)
        #expect(!t.visibleActivities.contains { $0.id == a })
        #expect(t.total(kind: .work, activity: a, in: everything, now: at(9000)) == 500)
    }

    @Test func deletingActivityRemovesItAndItsHistory() {
        var (t, a, b) = makeTracker()
        t.start(b, now: at(0), breakLength: breakLength)
        t.start(a, now: at(100), breakLength: breakLength)
        t.deleteActivity(a, now: at(400))

        #expect(t.phase == .idle)
        #expect(t.lastActivityID == nil)
        #expect(!t.activities.contains { $0.id == a })
        #expect(!t.entries.contains { $0.activityID == a })
        #expect(t.total(kind: .work, in: everything, now: at(9000)) == 100)
    }

    @Test func recoverClosesOpenEntryAtLastSeen() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.recover(lastSeen: at(500))

        #expect(t.phase == .idle)
        #expect(t.total(kind: .work, in: everything, now: at(10_000)) == 500)
    }

    @Test func resetBlockMovesNextBreakAFullBlockFromNow() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.resetBlock(now: at(2000))

        #expect(t.runningActivityID == a)
        #expect(t.nextBreak(now: at(2000), blockLength: blockLength) == at(5000))
        #expect(t.total(kind: .work, activity: a, in: everything, now: at(2500)) == 2500)
    }

    /// Work one full block starting at `start`, then begin a break. Returns the break start.
    private func workBlock(_ t: inout Tracker, _ id: UUID, from start: TimeInterval) -> TimeInterval {
        t.start(id, now: at(start), breakLength: breakLength, longBreakLength: 1200)
        t.beginBreak(now: at(start + blockLength), longBreakEvery: 3)
        return start + blockLength
    }

    @Test func everyNthBreakIsLongAndTakingItRestartsTheCount() {
        var (t, a, _) = makeTracker()
        var clock: TimeInterval = 0
        var kinds: [Bool] = []
        for _ in 0..<4 {
            clock = workBlock(&t, a, from: clock)
            kinds.append(t.isLongBreak)
            t.endBreak(now: at(clock + 60))
            t.pause(now: at(clock + 60))
            clock += 60
        }
        #expect(kinds == [false, false, true, false])
    }

    @Test func skippingLongBreakKeepsNextBreakLong() {
        var (t, a, _) = makeTracker()
        var clock: TimeInterval = 0
        for _ in 0..<2 {
            clock = workBlock(&t, a, from: clock)
            t.endBreak(now: at(clock))
            t.pause(now: at(clock))
        }
        clock = workBlock(&t, a, from: clock)
        #expect(t.isLongBreak)
        t.skipBreak(now: at(clock))
        #expect(!t.isLongBreak)
        #expect(t.nextBreakIsLong(longBreakEvery: 3))
    }

    @Test func longIdleGapRestartsSessionCount() {
        var (t, a, _) = makeTracker()
        let clock = workBlock(&t, a, from: 0)
        t.endBreak(now: at(clock))
        t.pause(now: at(clock))
        #expect(t.completedSessions == 1)
        t.start(a, now: at(clock + 1200), breakLength: breakLength, longBreakLength: 1200)
        #expect(t.completedSessions == 0)
    }

    @Test func snoozeDelaysBreakBySnoozeTimeAndKeepsWorkCounting() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.beginBreak(now: at(3000), longBreakEvery: 2)
        t.snoozeBreak(now: at(3005), blockLength: blockLength, snooze: 600)

        #expect(t.phase == .working)
        #expect(t.runningActivityID == a)
        #expect(!t.entries.contains { $0.kind == .breakTime })
        #expect(t.total(kind: .work, in: everything, now: at(3005)) == 3005)
        #expect(t.nextBreak(now: at(3005), blockLength: blockLength) == at(3600))
        #expect(!t.shouldBreak(now: at(3599), blockLength: blockLength))
        #expect(t.shouldBreak(now: at(3600), blockLength: blockLength))
        #expect(t.completedSessions == 0)
    }

    @Test func snoozedLongBreakComesBackLong() {
        var (t, a, _) = makeTracker()
        var clock: TimeInterval = 0
        for _ in 0..<2 {
            clock = workBlock(&t, a, from: clock)
            t.endBreak(now: at(clock))
            t.pause(now: at(clock))
        }
        clock = workBlock(&t, a, from: clock)  // third break: long (every 3)
        #expect(t.isLongBreak)
        t.snoozeBreak(now: at(clock), blockLength: blockLength, snooze: 300)
        #expect(t.completedSessions == 2)
        t.beginBreak(now: at(clock + 300), longBreakEvery: 3)
        #expect(t.isLongBreak)
    }

    @Test func breakOnRequestWhileIdleResumesLastActivity() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.pause(now: at(100))
        t.beginBreak(now: at(200))
        #expect(t.phase == .onBreak)
        t.endBreak(now: at(800))

        #expect(t.runningActivityID == a)
        #expect(t.total(kind: .breakTime, in: everything, now: at(900)) == 600)
        #expect(t.total(kind: .work, in: everything, now: at(900)) == 200)
    }

    @Test func breakOnRequestNeedsSomeActivity() {
        var t = Tracker()
        t.beginBreak(now: at(0))
        #expect(t.phase == .idle)
    }

    @Test func upgradingShortBreakToLongKeepsElapsedAndRestartsCycle() {
        var (t, a, _) = makeTracker()
        let clock = workBlock(&t, a, from: 0)  // first break: short (every 3)
        #expect(!t.isLongBreak)
        t.upgradeToLongBreak()
        #expect(t.isLongBreak)
        #expect(t.breakElapsed(now: at(clock + 400)) == 400)
        t.endBreak(now: at(clock + 1200))

        #expect(t.completedSessions == 0)
        #expect(t.total(kind: .breakTime, in: everything, now: at(clock + 1300)) == 1200)
    }

    @Test func mostRecentlyStartedActivityComesFirst() {
        var (t, a, b) = makeTracker()
        let c = t.addActivity(name: "C")
        #expect(t.activitiesByRecentUse.map(\.id) == [a, b, c])
        t.start(b, now: at(0), breakLength: breakLength)
        t.start(a, now: at(100), breakLength: breakLength)
        t.start(b, now: at(200), breakLength: breakLength)
        #expect(t.activitiesByRecentUse.map(\.id) == [b, a, c])
    }

    @Test func forcedLongBreakIsLongAndRestartsCycle() {
        var (t, a, _) = makeTracker()
        t.start(a, now: at(0), breakLength: breakLength)
        t.beginBreak(now: at(100), longBreakEvery: 4, forceLong: true)
        #expect(t.isLongBreak)
        t.endBreak(now: at(1300))
        #expect(t.completedSessions == 0)
    }

    @Test func decodesDataSavedBeforeLongBreaksExisted() throws {
        let json = #"{"activities":[],"blockAccumulated":120,"entries":[],"phase":"idle"}"#
        let t = try JSONDecoder().decode(Tracker.self, from: Data(json.utf8))
        #expect(t.blockAccumulated == 120)
        #expect(t.completedSessions == 0)
    }

    @Test func timeFormatting() {
        #expect(TimeFormat.long(5135) == "1h 25m 35s")
        #expect(TimeFormat.long(63) == "1m 3s")
        #expect(TimeFormat.short(5135) == "1h 25m")
        #expect(TimeFormat.clock(59.4) == "01:00")
        #expect(TimeFormat.clock(0) == "00:00")
        #expect(TimeFormat.clock(2952) == "49:12")
        #expect(TimeFormat.clock(3723) == "1:02:03")
        #expect(TimeFormat.minutesLeft(2952) == "50 minutes")
        #expect(TimeFormat.minutesLeft(30) == "1 minute")
        #expect(TimeFormat.minutesLeft(0) == "0 minutes")
    }
}
