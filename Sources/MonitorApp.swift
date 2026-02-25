import SwiftUI
import AppKit

/// Pure AppKit app — no SwiftUI lifecycle, full control over the window.
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!
    let screenGuardController = ScreenGuardController()
    var mainWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the main window manually
        createMainWindow()

        // Initialize status bar
        statusBarController = StatusBarController()
        statusBarController.setup(with: screenGuardController)

        // Request camera access
        screenGuardController.requestCameraAccess()

        // Show window
        showMainWindow()
    }

    private func createMainWindow() {
        let contentView = ContentView()
            .environmentObject(screenGuardController)

        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "屏幕卫士"
        mainWindow.center()
        mainWindow.contentView = NSHostingView(rootView: contentView)
        mainWindow.minSize = NSSize(width: 440, height: 560)
        mainWindow.isReleasedWhenClosed = false  // KEY: keep window alive after close
        mainWindow.delegate = self
    }

    func showMainWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close — window stays alive for re-show
        sender.orderOut(nil)
        return false
    }
}

// MARK: - App Entry Point

@main
enum MonitorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
