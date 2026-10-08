import Foundation

public enum Period: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    public var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

public extension Calendar {
    /// The current calendar day/week/month/year containing `date`.
    func periodInterval(_ period: Period, containing date: Date) -> DateInterval {
        dateInterval(of: period.component, for: date) ?? DateInterval(start: date, duration: 0)
    }
}

public extension Calendar {
    /// Sub-intervals for a period's chart: days of a week, weeks of a month (clipped to the month), months of a year.
    func chartBuckets(_ period: Period, containing date: Date) -> [DateInterval] {
        let range = periodInterval(period, containing: date)
        let sub: Period = switch period {
        case .day, .week: .day
        case .month: .week
        case .year: .month
        }
        var buckets: [DateInterval] = []
        var cursor = range.start
        while cursor < range.end {
            let interval = periodInterval(sub, containing: cursor)
            guard interval.end > cursor else { break }
            buckets.append(DateInterval(start: max(interval.start, range.start), end: min(interval.end, range.end)))
            cursor = interval.end
        }
        return buckets
    }
}
