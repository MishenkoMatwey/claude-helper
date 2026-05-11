import SwiftUI
import AppKit

@main
struct ClaudeAgentsMonitorApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                Text(state.tokensVM.menuBarLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)

        Window("Claude Agents", id: "dashboard") {
            DashboardView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        speedUpTooltips()
        NotificationService.requestAuthorization()
    }

    /// Reduce system tooltip delay from ~1500ms to 300ms via runtime KVC on
    /// NSToolTipManager (private but stable API).
    private func speedUpTooltips() {
        guard let cls = NSClassFromString("NSToolTipManager") as? NSObject.Type else { return }
        let sel = NSSelectorFromString("sharedToolTipManager")
        guard cls.responds(to: sel) else { return }
        let mgr = cls.perform(sel)?.takeUnretainedValue()
        (mgr as? NSObject)?.setValue(0.30, forKey: "initialToolTipDelay")
    }
}
