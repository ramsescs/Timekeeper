import Foundation

public enum Phase: String, Codable, Sendable {
    case idle, working, onBreak
}

/// The whole app state and its state machine. Every mutation takes `now` so it is deterministic to test.
/// Totals are always derived from entry timestamps, never from counting ticks.
public struct Tracker: Codable, Equatable, Sendable {
    public var activities: [Activity] = []
    public var entries: [TimeEntry] = []
    public private(set) var phase: Phase = .idle
    /// Activity being tracked; during a break, the one to resume afterwards.
    public private(set) var runningActivityID: UUID?
    /// Last activity that ran, so Resume knows what to restart.
    public private(set) var lastActivityID: UUID?
    /// Closed work seconds in the current block; the open work entry is added on top.
    public private(set) var blockAccumulated: TimeInterval = 0
    public private(set) var idleSince: Date?
    public private(set) var breakStartedAt: Date?
    /// Work blocks finished since the last long break.
    public private(set) var completedSessions: Int = 0
    public private(set) var isLongBreak: Bool = false

    public init() {}

    // Decode field by field so data saved by older versions (missing newer keys) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        entries = try c.decodeIfPresent([TimeEntry].self, forKey: .entries) ?? []
        phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .idle
        runningActivityID = try c.decodeIfPresent(UUID.self, forKey: .runningActivityID)
        lastActivityID = try c.decodeIfPresent(UUID.self, forKey: .lastActivityID)
        blockAccumulated = try c.decodeIfPresent(TimeInterval.self, forKey: .blockAccumulated) ?? 0
        idleSince = try c.decodeIfPresent(Date.self, forKey: .idleSince)
        breakStartedAt = try c.decodeIfPresent(Date.self, forKey: .breakStartedAt)
        completedSessions = try c.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        isLongBreak = try c.decodeIfPresent(Bool.self, forKey: .isLongBreak) ?? false
    }

    public static let palette = ["#4A90E2", "#50C878", "#E5534B", "#F5A623", "#9B59B6", "#1ABC9C", "#E67E22", "#EC407A"]

    // MARK: Activities

    public var visibleActivities: [Activity] { activities.filter { !$0.archived } }

    /// Visible activities, most recently started first; never-started ones follow in creation order.
    public var activitiesByRecentUse: [Activity] {
        var lastStart: [UUID: Date] = [:]
        for e in entries where e.kind == .work {
            if let id = e.activityID, e.start > lastStart[id] ?? .distantPast { lastStart[id] = e.start }
        }
        return visibleActivities.enumerated().sorted { a, b in
            let (da, db) = (lastStart[a.element.id] ?? .distantPast, lastStart[b.element.id] ?? .distantPast)
            return da != db ? da > db : a.offset < b.offset
        }.map(\.element)
    }

    @discardableResult
    public mutating func addActivity(name: String) -> UUID {
        let activity = Activity(name: name, colorHex: Self.palette[activities.count % Self.palette.count])
        activities.append(activity)
        return activity.id
    }

    public mutating func rename(_ id: UUID, to name: String) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[i].name = name
    }

    public mutating func archive(_ id: UUID, now: Date) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        if runningActivityID == id { pause(now: now) }
        if lastActivityID == id { lastActivityID = nil }
        activities[i].archived = true
    }

    /// Permanently remove an activity and all its work history.
    public mutating func deleteActivity(_ id: UUID, now: Date) {
        if runningActivityID == id {
            guard phase == .working else { return }
            pause(now: now)
        }
        if lastActivityID == id { lastActivityID = nil }
        entries.removeAll { $0.activityID == id }
        activities.removeAll { $0.id == id }
    }

    // MARK: Queries

    private var openIndex: Int? { entries.lastIndex { $0.end == nil } }

    public func blockElapsed(now: Date) -> TimeInterval {
        guard phase == .working, let i = openIndex else { return blockAccumulated }
        return blockAccumulated + entries[i].duration(now: now)
    }

    public func shouldBreak(now: Date, blockLength: TimeInterval) -> Bool {
        phase == .working && blockElapsed(now: now) >= blockLength
    }

    public func nextBreak(now: Date, blockLength: TimeInterval) -> Date? {
        guard phase == .working else { return nil }
        return now.addingTimeInterval(max(0, blockLength - blockElapsed(now: now)))
    }

    /// Whether the upcoming break will be a long one (`longBreakEvery` nil = long breaks off).
    public func nextBreakIsLong(longBreakEvery: Int?) -> Bool {
        guard let every = longBreakEvery, every > 0 else { return false }
        return completedSessions + 1 >= every
    }

    public func breakElapsed(now: Date) -> TimeInterval {
        guard phase == .onBreak, let start = breakStartedAt else { return 0 }
        return now.timeIntervalSince(start)
    }

    /// Sum of entries of `kind` (optionally one activity), clipped to `interval` so spans crossing midnight split correctly.
    public func total(kind: EntryKind, activity: UUID? = nil, in interval: DateInterval, now: Date) -> TimeInterval {
        entries.reduce(0) { sum, e in
            guard e.kind == kind, activity == nil || e.activityID == activity else { return sum }
            let start = max(e.start, interval.start)
            let end = min(e.end ?? now, interval.end)
            return sum + max(0, end.timeIntervalSince(start))
        }
    }

    // MARK: Transitions

    @discardableResult
    private mutating func closeOpen(at now: Date) -> TimeInterval {
        guard let i = openIndex else { return 0 }
        let end = max(now, entries[i].start)
        entries[i].end = end
        return end.timeIntervalSince(entries[i].start)
    }

    /// Start (or switch to) an activity. Switching pauses the previous one; an idle gap ≥ `breakLength` counts as a rest and resets the block,
    /// and one ≥ `longBreakLength` also resets the session count.
    public mutating func start(_ id: UUID, now: Date, breakLength: TimeInterval, longBreakLength: TimeInterval? = nil) {
        switch phase {
        case .onBreak:
            return
        case .working:
            guard id != runningActivityID else { return }
            blockAccumulated += closeOpen(at: now)
        case .idle:
            if let idleSince {
                let gap = now.timeIntervalSince(idleSince)
                if gap >= breakLength { blockAccumulated = 0 }
                if let longBreakLength, gap >= longBreakLength { completedSessions = 0 }
            }
        }
        entries.append(TimeEntry(kind: .work, activityID: id, start: now))
        phase = .working
        runningActivityID = id
        lastActivityID = id
        idleSince = nil
    }

    /// Pause work, or end a break early (e.g. on sleep) so the gap isn't logged.
    public mutating func pause(now: Date) {
        switch phase {
        case .idle:
            return
        case .working:
            blockAccumulated += closeOpen(at: now)
        case .onBreak:
            closeOpen(at: now)
            blockAccumulated = 0
            breakStartedAt = nil
            finishBreak(taken: true)
        }
        phase = .idle
        runningActivityID = nil
        idleSince = now
    }

    /// Restart the block so the next break is a full block from `now`. Work keeps counting for the same activity.
    public mutating func resetBlock(now: Date) {
        guard phase != .onBreak else { return }
        blockAccumulated = 0
        if phase == .working, let id = runningActivityID {
            closeOpen(at: now)
            entries.append(TimeEntry(kind: .work, activityID: id, start: now))
        }
    }

    /// The block is done (or a break was requested): count the session and decide whether this is the long break.
    /// From idle, the break resumes the last activity afterwards.
    public mutating func beginBreak(now: Date, longBreakEvery: Int? = nil, forceLong: Bool = false) {
        switch phase {
        case .working: break
        case .idle:
            guard let last = lastActivityID else { return }
            runningActivityID = last
            idleSince = nil
        case .onBreak: return
        }
        isLongBreak = forceLong || nextBreakIsLong(longBreakEvery: longBreakEvery)
        completedSessions += 1
        closeOpen(at: now)
        entries.append(TimeEntry(kind: .breakTime, activityID: nil, start: now))
        phase = .onBreak
        breakStartedAt = now
        blockAccumulated = 0
    }

    /// The break never happened: drop it and resume work from when it began. A new block starts at that moment.
    public mutating func skipBreak(now: Date) {
        guard phase == .onBreak, let start = breakStartedAt, let id = runningActivityID else { return }
        if let i = openIndex, entries[i].kind == .breakTime { entries.remove(at: i) }
        entries.append(TimeEntry(kind: .work, activityID: id, start: start))
        phase = .working
        breakStartedAt = nil
        blockAccumulated = 0
        finishBreak(taken: false)
    }

    /// Postpone the break: drop it, keep working from when it began, and bring it back `snooze` seconds after it was due.
    /// The session isn't counted yet, so the returning break is the same kind (short/long).
    public mutating func snoozeBreak(now: Date, blockLength: TimeInterval, snooze: TimeInterval) {
        guard phase == .onBreak, let start = breakStartedAt, let id = runningActivityID else { return }
        if let i = openIndex, entries[i].kind == .breakTime { entries.remove(at: i) }
        entries.append(TimeEntry(kind: .work, activityID: id, start: start))
        phase = .working
        breakStartedAt = nil
        blockAccumulated = max(0, blockLength - snooze)
        completedSessions = max(0, completedSessions - 1)
        isLongBreak = false
    }

    /// Turn the running short break into the long break; time already rested counts toward it.
    public mutating func upgradeToLongBreak() {
        guard phase == .onBreak else { return }
        isLongBreak = true
    }

    /// "Back to work": close the break and resume the same activity with a fresh block.
    public mutating func endBreak(now: Date) {
        guard phase == .onBreak, let id = runningActivityID else { return }
        closeOpen(at: now)
        entries.append(TimeEntry(kind: .work, activityID: id, start: now))
        phase = .working
        breakStartedAt = nil
        blockAccumulated = 0
        finishBreak(taken: true)
    }

    /// A taken long break restarts the session count; a skipped one leaves it, so the next break is long again.
    private mutating func finishBreak(taken: Bool) {
        if taken && isLongBreak { completedSessions = 0 }
        isLongBreak = false
    }

    /// After a crash, close whatever was open at the last heartbeat and go idle.
    public mutating func recover(lastSeen: Date) {
        closeOpen(at: lastSeen)
        guard phase != .idle else { return }
        phase = .idle
        runningActivityID = nil
        breakStartedAt = nil
        isLongBreak = false
        idleSince = lastSeen
    }
}
