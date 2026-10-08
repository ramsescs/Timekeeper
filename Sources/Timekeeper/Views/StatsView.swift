import SwiftUI
import TimekeeperCore

struct StatsView: View {
    let model: AppModel
    @State private var period: Period = .week
    @State private var pendingDeleteID: UUID?

    var body: some View {
        let tracker = model.tracker
        let interval = Calendar.current.periodInterval(period, containing: model.now)
        let rows = tracker.activities
            .map { (activity: $0, total: tracker.total(kind: .work, activity: $0.id, in: interval, now: model.now)) }
            .filter { $0.total > 0 || !$0.activity.archived }
            .sorted { $0.total > $1.total }
        let maxTotal = rows.map(\.total).max() ?? 0

        VStack(alignment: .leading, spacing: 14) {
            Text("Stats").font(.largeTitle.bold())

            Picker("Period", selection: $period) {
                Text("Week").tag(Period.week)
                Text("Month").tag(Period.month)
                Text("Year").tag(Period.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                StatTile(title: "💻 Work", value: tracker.total(kind: .work, in: interval, now: model.now), color: .blue)
                StatTile(title: "🧘 Break", value: tracker.total(kind: .breakTime, in: interval, now: model.now), color: .green)
            }

            PeriodChart(model: model, period: period)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.activity.id) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.activity.name + (row.activity.archived ? " (deleted)" : "")).lineLimit(1)
                                Spacer()
                                Text(TimeFormat.long(row.total)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color(hex: row.activity.colorHex))
                                    .frame(width: maxTotal > 0 ? geo.size.width * row.total / maxTotal : 0)
                            }
                            .frame(height: 6)
                            if pendingDeleteID == row.activity.id {
                                HStack {
                                    Text("Delete it and all its time? This can't be undone.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Cancel") { pendingDeleteID = nil }
                                    Button("Delete", role: .destructive) {
                                        model.deletePermanently(row.activity.id)
                                        pendingDeleteID = nil
                                    }
                                    .tint(.red)
                                }
                                .controlSize(.small)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Delete Permanently…", role: .destructive) { pendingDeleteID = row.activity.id }
                        }
                    }
                }
            }
        }
    }
}
