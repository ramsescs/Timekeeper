import SwiftUI
import TimekeeperCore

struct TodayView: View {
    let model: AppModel
    @State private var newName = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today").font(.largeTitle.bold())
                Spacer()
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
            }

            HStack(spacing: 10) {
                StatTile(title: "💻 Work", value: model.todayTotal(.work), color: .blue)
                StatTile(title: "🧘 Break", value: model.todayTotal(.breakTime), color: .green)
            }

            Text(statusLine).foregroundStyle(.secondary)

            if let every = model.longBreakEvery, every > 0 {
                SessionDots(done: model.tracker.completedSessions, total: every, working: model.tracker.phase == .working)
            }

            if model.tracker.phase == .working || model.tracker.lastActivityID != nil {
                HStack {
                    switch model.tracker.phase {
                    case .working:
                        Button { model.pauseOrResume() } label: { Label("Pause", systemImage: "pause.fill") }
                    case .idle:
                        Button { model.pauseOrResume() } label: { Label("Resume", systemImage: "play.fill") }
                    case .onBreak:
                        EmptyView()
                    }
                    if model.tracker.phase != .onBreak {
                        Button { model.resetBlock() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                            .help("Next break a full work block from now")
                    }
                }
                if model.tracker.phase != .onBreak {
                    HStack {
                        Button { model.takeBreak() } label: { Text("☕ Short break").frame(maxWidth: .infinity) }
                            .help("Start a short break now")
                        if model.longBreakEvery != nil {
                            Button { model.takeBreak(long: true) } label: { Text("💤 Long break").frame(maxWidth: .infinity) }
                                .help("Start a long break now")
                        }
                    }
                }
            }

            Text("Activities").font(.headline)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.tracker.activitiesByRecentUse) { activity in
                        row(activity)
                    }
                }
            }

            TextField("+ New activity", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.addActivity(named: newName)
                    newName = ""
                }
        }
    }

    private var statusLine: String {
        switch model.tracker.phase {
        case .working:
            guard let next = model.nextBreak else { return "" }
            let time = next.formatted(date: .omitted, time: .shortened)
            return model.nextBreakIsLong ? "Long break at \(time)" : "Next break at \(time)"
        case .onBreak: return "On a break"
        case .idle: return "Not tracking"
        }
    }

    @ViewBuilder
    private func row(_ activity: Activity) -> some View {
        let color = Color(hex: activity.colorHex)
        let running = model.tracker.phase == .working && model.tracker.runningActivityID == activity.id

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 24)
            if renamingID == activity.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.rename(activity.id, to: renameText)
                        renamingID = nil
                    }
            } else {
                Text(activity.name).lineLimit(1)
            }
            Spacer()
            Text(TimeFormat.long(model.todayTotal(.work, activity: activity.id)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button { model.toggle(activity.id) } label: {
                Image(systemName: running ? "pause.circle.fill" : "play.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(running ? color.opacity(0.18) : Color.primary.opacity(0.05)))
        .contextMenu {
            Button("Rename") {
                renameText = activity.name
                renamingID = activity.id
            }
            Button("Delete", role: .destructive) { model.archive(activity.id) }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: TimeInterval
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            VStack(spacing: 4) {
                Text(value > 0 ? TimeFormat.long(value) : "–").font(.headline).monospacedDigit()
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Progress through the long-break cycle: ● done, ◯ current, faint = still to go; the last dot ends in the long break.
struct SessionDots: View {
    let done: Int
    let total: Int
    let working: Bool

    var body: some View {
        let filled = min(done, total)
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                ZStack {
                    if i < filled {
                        Circle().fill(Color.green)
                    } else if i == filled && working {
                        Circle().strokeBorder(Color.green, lineWidth: 2)
                    } else {
                        Circle().fill(Color.primary.opacity(0.12))
                    }
                    if i == total - 1 {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(i < filled ? Color.white : Color.secondary)
                    }
                }
                .frame(width: 14, height: 14)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .help("Work sessions in this long-break cycle")
    }

    private var caption: String {
        if done >= total { return "Long break due" }
        return "\(done) of \(total) sessions for the next long break"
    }
}
