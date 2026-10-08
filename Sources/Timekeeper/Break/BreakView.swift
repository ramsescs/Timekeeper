import SwiftUI
import TimekeeperCore

struct BreakView: View {
    let model: AppModel
    @State private var customSnooze = false
    @State private var customMinutes: Int?

    var body: some View {
        let elapsed = model.tracker.breakElapsed(now: model.now)
        let length = max(model.currentBreakLength, 1)
        let remaining = max(0, length - elapsed)

        VStack(spacing: 28) {
            Spacer()
            if model.tracker.isLongBreak {
                Text("LONG BREAK")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .opacity(0.7)
            }
            Text(model.breakMessage)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .opacity(0.85)
            ProgressView(value: min(elapsed / length, 1))
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(width: 280)
            Text(TimeFormat.clock(remaining))
                .font(.system(size: 80, weight: .semibold, design: .rounded))
                .monospacedDigit()
            // Main actions, right under the timer.
            VStack(spacing: 14) {
                if remaining == 0 {
                    Button("Back to work") { model.endBreak() }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(model.snoozeMinutes == 1 ? "Snooze for 1 minute" : "Snooze for \(model.snoozeMinutes) minutes") {
                        model.snoozeBreak()
                    }
                    .controlSize(.large)
                    customSnoozeControl
                        .font(.callout)
                        .opacity(customSnooze ? 1 : 0.6)
                    Button("Skip") { model.skipBreak() }
                        .keyboardShortcut(customSnooze ? nil : .cancelAction)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .opacity(0.6)
                }
            }
            Spacer()
            // Secondary actions, discreet at the bottom.
            VStack(spacing: 10) {
                if canStartLongBreak(elapsed: elapsed) {
                    Button("Start long break") { model.startLongBreak() }
                }
                Button("Pause Timekeeper") { model.pauseFromBreak() }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .opacity(0.5)
        }
        .foregroundStyle(.white)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
    }

    /// A discreet "Custom…" link that expands into a minutes field for a one-off snooze length.
    @ViewBuilder
    private var customSnoozeControl: some View {
        if customSnooze {
            HStack(spacing: 6) {
                TextField("min", value: $customMinutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .onSubmit(snoozeCustom)
                Text("min")
                Button("Snooze", action: snoozeCustom)
                    .disabled(validCustomMinutes == nil)
                Button("Cancel") { customSnooze = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .opacity(0.7)
            }
        } else {
            Button("Custom…") {
                customMinutes = model.snoozeMinutes
                customSnooze = true
            }
            .buttonStyle(.plain)
        }
    }

    private var validCustomMinutes: Int? {
        guard let m = customMinutes, (1...240).contains(m) else { return nil }
        return m
    }

    private func snoozeCustom() {
        guard let minutes = validCustomMinutes else { return }
        model.snoozeBreak(minutes: minutes)
    }

    /// Offered on a short break while long breaks are on and the long break would still have time left.
    private func canStartLongBreak(elapsed: TimeInterval) -> Bool {
        !model.tracker.isLongBreak && model.longBreakEvery != nil && elapsed < model.longBreakLength
    }
}
