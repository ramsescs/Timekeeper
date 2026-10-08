import Charts
import SwiftUI
import TimekeeperCore

/// Stacked work-hours bars for a period: days of the week, weeks of the month, or months of the year.
/// Segments use each activity's own color; the activity rows below the chart act as its legend.
struct PeriodChart: View {
    let model: AppModel
    let period: Period
    @State private var hovered: String?

    private struct Bucket {
        let label: String
        let interval: DateInterval
    }

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let colorHex: String
        let hours: Double
    }

    var body: some View {
        let tracker = model.tracker
        let buckets = Calendar.current.chartBuckets(period, containing: model.now).map {
            Bucket(label: label(for: $0), interval: $0)
        }
        let segments = buckets.flatMap { bucket in
            tracker.activities.compactMap { activity -> Segment? in
                let seconds = tracker.total(kind: .work, activity: activity.id, in: bucket.interval, now: model.now)
                guard seconds > 0 else { return nil }
                return Segment(id: bucket.label + activity.id.uuidString, label: bucket.label,
                               colorHex: activity.colorHex, hours: seconds / 3600)
            }
        }

        Chart {
            ForEach(segments) { segment in
                BarMark(x: .value("Period", segment.label), y: .value("Hours", segment.hours), width: .ratio(0.6))
                    .foregroundStyle(Color(hex: segment.colorHex))
            }
            if let hovered, let bucket = buckets.first(where: { $0.label == hovered }) {
                RuleMark(x: .value("Period", hovered))
                    .foregroundStyle(Color.primary.opacity(0.08))
                    .lineStyle(StrokeStyle(lineWidth: 18))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(bucket)
                    }
            }
        }
        .chartXScale(domain: buckets.map(\.label))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(hours, format: .number.precision(.fractionLength(0...1)))h") }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let originX = proxy.plotFrame.map { geo[$0].origin.x } ?? 0
                            hovered = proxy.value(atX: location.x - originX, as: String.self)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .overlay {
            if segments.isEmpty {
                Text("No work tracked yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 120)
    }

    private func tooltip(_ bucket: Bucket) -> some View {
        let total = model.tracker.total(kind: .work, in: bucket.interval, now: model.now)
        return VStack(spacing: 2) {
            Text(tooltipTitle(bucket.interval)).font(.caption2).foregroundStyle(.secondary)
            Text(total > 0 ? TimeFormat.long(total) : "–").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
    }

    /// Axis label, unique per bucket: "Mon", "Oct 5", "Jan".
    private func label(for interval: DateInterval) -> String {
        switch period {
        case .day, .week: interval.start.formatted(.dateTime.weekday(.abbreviated))
        case .month: interval.start.formatted(.dateTime.month(.abbreviated).day())
        case .year: interval.start.formatted(.dateTime.month(.abbreviated))
        }
    }

    private func tooltipTitle(_ interval: DateInterval) -> String {
        switch period {
        case .day, .week:
            return interval.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .month:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.day()))"
        case .year:
            return interval.start.formatted(.dateTime.month(.wide))
        }
    }
}
