import SwiftUI
import AppKit

/// Pure AppKit app — no SwiftUI lifecycle, full control over the window.
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!
    let screenGuardController = ScreenGuardController()
    var mainWindow: NSWindow!

    /// Holds references to event monitors so they stay alive for the app's lifetime.
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the main window manually
        createMainWindow()

        // Register global hotkeys (work even when another app is in the foreground)
        registerGlobalHotkeys()

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

    // MARK: - Global Hotkeys

    /// Registers both a **global** monitor (fires when OTHER apps are active)
    /// and a **local** monitor (fires when THIS app is active).
    /// This ensures the hotkey works no matter which app is in the foreground.
    ///
    /// Hotkeys:
    ///   • Cmd+Shift+M  → toggle monitoring on/off
    ///   • Cmd+Shift+0  → show main window
    private func registerGlobalHotkeys() {
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event // pass the event through (required for local monitor)
        }

        // Global monitor — triggers when our app is NOT the active app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }

        // Local monitor — triggers when our app IS the active app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Shift+M → toggle monitoring
        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "m" {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.screenGuardController.isMonitoring {
                    self.screenGuardController.stopMonitoring()
                } else {
                    self.screenGuardController.startMonitoring()
                }
            }
            return
        }

        // Cmd+Shift+0 → show main window
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "0" {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return
        }
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
