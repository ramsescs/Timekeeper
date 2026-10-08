import AppKit
import SwiftUI
import TimekeeperCore

@main
struct TimekeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        switch model.tracker.phase {
        case .working:
            // Countdown to the next break.
            HStack(spacing: 4) {
                Image(nsImage: RobotIcon.image)
                Text(TimeFormat.minutesLeft(model.blockLength - model.tracker.blockElapsed(now: model.now)))
                    .monospacedDigit()
            }
        case .onBreak:
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer")
                Text(TimeFormat.minutesLeft(model.currentBreakLength - model.tracker.breakElapsed(now: model.now)))
                    .monospacedDigit()
            }
        case .idle:
            Image(nsImage: RobotIcon.image)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, even when run unbundled via `swift run`.
        NSApp.setActivationPolicy(.accessory)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.handleSleep() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.handleSleep() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}
