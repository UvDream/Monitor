import SwiftUI
import AppKit

/// Custom NSApplicationDelegate to initialize the status bar early in the app lifecycle.
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!
    let screenGuardController = ScreenGuardController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize status bar
        statusBarController = StatusBarController()
        statusBarController.setup(with: screenGuardController)

        // Request camera access on launch
        screenGuardController.requestCameraAccess()

        // Show the main window on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    /// Keep app alive when all windows are closed (menu bar mode)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.screenGuardController)
        }
        .defaultSize(width: 480, height: 620)
    }
}
