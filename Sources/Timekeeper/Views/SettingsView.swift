import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.blockMinutes) private var blockMinutes = SettingsKey.defaultBlockMinutes
    @AppStorage(SettingsKey.breakMinutes) private var breakMinutes = SettingsKey.defaultBreakMinutes
    @AppStorage(SettingsKey.breakMessage) private var breakMessage = SettingsKey.defaultBreakMessage
    @AppStorage(SettingsKey.longBreakEnabled) private var longBreakEnabled = SettingsKey.defaultLongBreakEnabled
    @AppStorage(SettingsKey.longBreakEvery) private var longBreakEvery = SettingsKey.defaultLongBreakEvery
    @AppStorage(SettingsKey.longBreakMinutes) private var longBreakMinutes = SettingsKey.defaultLongBreakMinutes
    @AppStorage(SettingsKey.snoozeMinutes) private var snoozeMinutes = SettingsKey.defaultSnoozeMinutes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.largeTitle.bold())

                MinutesField(title: "Work block", value: $blockMinutes, range: 1...240)
                MinutesField(title: "Break length", value: $breakMinutes, range: 1...60)
                MinutesField(title: "Snooze", value: $snoozeMinutes, range: 1...60)

                LaunchAtLoginToggle()

                Toggle("Long breaks", isOn: $longBreakEnabled)
                if longBreakEnabled {
                    MinutesField(title: "Long break length", value: $longBreakMinutes, range: 1...120)
                    MinutesField(title: "Every", value: $longBreakEvery, range: 2...12, unit: "sessions")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Break message")
                    TextField("Break message", text: $breakMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }

                PhoneNotifySettings()

                Text("A break screen appears after each work block. Pausing or stepping away for at least the break length also starts a fresh block.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
        }
    }
}

/// Typeable minutes with a stepper beside it; out-of-range input is clamped.
struct MinutesField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit = "min"

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .labelsHidden()
            Text(unit).foregroundStyle(.secondary)
            Stepper(title, value: $value, in: range).labelsHidden()
        }
        .onChange(of: value) { _, new in
            let clamped = min(max(new, range.lowerBound), range.upperBound)
            if clamped != new { value = clamped }
        }
    }
}

/// Mirrors the system login-item state (System Settings → General → Login Items) rather than storing its own copy.
struct LaunchAtLoginToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(get: { isOn }, set: { update($0) }))
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
    }

    private func update(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            note = nil
        } catch {
            note = "Couldn't change this: \(error.localizedDescription)"
        }
        refresh()
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        if status == .requiresApproval {
            note = "Approve Timekeeper in System Settings → General → Login Items."
        }
    }
}

struct PhoneNotifySettings: View {
    @AppStorage(SettingsKey.phoneNotify) private var enabled = SettingsKey.defaultPhoneNotify
    @AppStorage(SettingsKey.ntfyTopic) private var topic = ""
    @State private var testStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Notify my phone when a break ends", isOn: $enabled)
            if enabled {
                HStack {
                    TextField("ntfy topic", text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Send test", action: sendTest)
                        .disabled(!PhoneNotifier.isValid(topic: topic))
                }
                Text(testStatus ?? "Install the ntfy app on your phone and subscribe to this topic. Anyone who knows the topic name can read it, so keep it random.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func sendTest() {
        testStatus = "Sending…"
        let topic = topic
        Task {
            do {
                try await PhoneNotifier.send(topic: topic, title: "Timekeeper test", message: "Phone notifications are working.", tags: "robot")
                testStatus = "Sent — check your phone."
            } catch {
                testStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
