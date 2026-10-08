import Foundation

public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// Deleted activities are archived: hidden from Today, kept in Stats.
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, colorHex: String, archived: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.archived = archived
    }
}

public enum EntryKind: String, Codable, Sendable {
    case work
    case breakTime
}

/// One contiguous span of work (for an activity) or break. `end == nil` means still running.
public struct TimeEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: EntryKind
    public var activityID: UUID?
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), kind: EntryKind, activityID: UUID?, start: Date, end: Date? = nil) {
        self.id = id
        self.kind = kind
        self.activityID = activityID
        self.start = start
        self.end = end
    }

    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

public enum TimeFormat {
    /// "1h 25m 35s", "25m 3s", "4s"
    public static func long(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// "1h 25m", "25m"
    public static func short(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let (h, m) = (t / 3600, (t % 3600) / 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Remaining time in whole minutes, rounded up: "49 minutes", "1 minute".
    public static func minutesLeft(_ seconds: TimeInterval) -> String {
        let m = Int((max(0, seconds) / 60).rounded(.up))
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    /// Countdown "MM:SS" (or "H:MM:SS" from an hour up), rounded up so it only shows 00:00 when time is truly up.
    public static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(max(0, seconds).rounded(.up))
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
