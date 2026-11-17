import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSUserNotificationCenter.default.delegate = self
        menuBar = MenuBarController()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool { true }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        guard notification.activationType == .actionButtonClicked,
              let id = notification.identifier,
              id.hasPrefix("am.runaway."),
              let pid = pid_t(id.replacingOccurrences(of: "am.runaway.", with: "")) else { return }
        ProcessActions.apply(.forceKill, to: pid)
    }
}
