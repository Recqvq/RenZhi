import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    private let model = AttendanceModel()
    private var panel: NSPanel!
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: AppConfiguration.windowWidth, height: AppConfiguration.windowHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "认知统计"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatingWidgetView(model: model, openAttendance: openAttendance))
        if !panel.setFrameUsingName("SentinelCompactWindow"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 328, y: screen.maxY - 54))
        }
        // Recover a saved window that belonged to a disconnected monitor.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        panel.setFrameAutosaveName("SentinelCompactWindow")
        Publishers.CombineLatest(model.$needsConnection, model.$minutes)
            .receive(on: RunLoop.main)
            .sink { [weak self] needsConnection, minutes in
                guard let panel = self?.panel else { return }
                let top = panel.frame.maxY
                let height: CGFloat = needsConnection && minutes == nil ? AppConfiguration.connectionHeight : AppConfiguration.windowHeight
                panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: AppConfiguration.windowWidth, height: height), display: true)
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.handleClockChange() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemClockDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.model.handleClockChange() }.store(in: &subscriptions)
        model.$pinned.sink { [weak self] pinned in self?.panel.level = pinned ? .floating : .normal }.store(in: &subscriptions)
        panel.orderFrontRegardless()
        model.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(); panel?.saveFrame(usingName: "SentinelCompactWindow")
    }
    func openAttendance() {
        model.connect()
        let url = AppConfiguration.attendanceURL
        NSWorkspace.shared.open(url)
        // Retry while Feishu creates its normal attendance session.
        for delay in [3.0, 8.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.model.refresh(reconnect: true) }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
