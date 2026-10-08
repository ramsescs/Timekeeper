import Foundation
import Testing
@testable import TimekeeperCore

struct StatsTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    @Test func entrySpanningMidnightSplitsAcrossDays() {
        var t = Tracker()
        let a = t.addActivity(name: "A")
        // Mon 2026-10-05 23:00 → Tue 01:00
        t.entries = [TimeEntry(kind: .work, activityID: a, start: date(2026, 10, 5, 23), end: date(2026, 10, 6, 1))]

        let mon = calendar.periodInterval(.day, containing: date(2026, 10, 5, 12))
        let tue = calendar.periodInterval(.day, containing: date(2026, 10, 6, 12))
        #expect(t.total(kind: .work, in: mon, now: .now) == 3600)
        #expect(t.total(kind: .work, in: tue, now: .now) == 3600)
    }

    @Test func weekMonthYearSums() {
        var t = Tracker()
        let a = t.addActivity(name: "A")
        let b = t.addActivity(name: "B")
        t.entries = [
            TimeEntry(kind: .work, activityID: a, start: date(2026, 10, 5, 9), end: date(2026, 10, 5, 11)),  // this week
            TimeEntry(kind: .work, activityID: b, start: date(2026, 10, 1, 9), end: date(2026, 10, 1, 10)),  // last week, this month
            TimeEntry(kind: .work, activityID: a, start: date(2026, 3, 2, 9), end: date(2026, 3, 2, 12)),    // this year
            TimeEntry(kind: .work, activityID: a, start: date(2025, 12, 1, 9), end: date(2025, 12, 1, 10)),  // last year
            TimeEntry(kind: .breakTime, activityID: nil, start: date(2026, 10, 5, 11), end: date(2026, 10, 5, 12)),
        ]
        let now = date(2026, 10, 5, 12)
        let week = calendar.periodInterval(.week, containing: now)
        let month = calendar.periodInterval(.month, containing: now)
        let year = calendar.periodInterval(.year, containing: now)

        #expect(t.total(kind: .work, in: week, now: now) == 2 * 3600)
        #expect(t.total(kind: .work, in: month, now: now) == 3 * 3600)
        #expect(t.total(kind: .work, activity: b, in: month, now: now) == 3600)
        #expect(t.total(kind: .work, activity: a, in: year, now: now) == 5 * 3600)
        #expect(t.total(kind: .breakTime, in: week, now: now) == 3600)
    }

    @Test func chartBucketsSplitPeriodsIntoDaysWeeksMonths() {
        let now = date(2026, 10, 7, 12)
        #expect(calendar.chartBuckets(.week, containing: now).count == 7)

        // Oct 2026 starts on a Thursday: Oct 1–4, 5–11, 12–18, 19–25, 26–31
        let weeks = calendar.chartBuckets(.month, containing: now)
        #expect(weeks.count == 5)
        #expect(weeks.first?.start == date(2026, 10, 1, 0))
        #expect(weeks.last?.end == date(2026, 11, 1, 0))

        #expect(calendar.chartBuckets(.year, containing: now).count == 12)
    }
}
