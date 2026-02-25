import AppKit
import SwiftUI
import Combine

/// Manages the macOS menu bar (status bar) icon and menu.
/// Shows current monitoring state via icon changes, and provides
/// quick controls to start/stop monitoring, show/hide the main window, and quit.
class StatusBarController: NSObject, ObservableObject {

    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private weak var controller: ScreenGuardController?

    // Menu items that need dynamic title updates
    private var toggleMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var faceCountMenuItem: NSMenuItem!

    // FIX: Pre-render all four icons exactly once and cache them.
    // Previously makeIcon() was called on every state change (every 200 ms at peak),
    // recreating an NSImage each time. Now each state maps to a single cached image.
    private lazy var iconCache: [IconState: NSImage] = {
        var cache: [IconState: NSImage] = [:]
        for state in IconState.allCases {
            cache[state] = makeIcon(state: state)
        }
        return cache
    }()

    func setup(with controller: ScreenGuardController) {
        self.controller = controller

        // Create status bar item with variable length to show face count
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = iconCache[.idle]
            button.imagePosition = .imageLeading
            button.title = "0"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.toolTip = "屏幕卫士"
        }

        // Build menu
        buildMenu()

        // Observe controller state changes to update icon and menu
        controller.$isMonitoring
            .combineLatest(controller.$threatDetected, controller.$isCalibrated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (monitoring, threat, calibrated) in
                self?.updateAppearance(monitoring: monitoring, threat: threat, calibrated: calibrated)
            }
            .store(in: &cancellables)

        controller.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.statusMenuItem?.title = "状态: \(msg)"
            }
            .store(in: &cancellables)

        controller.$faceCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.faceCountMenuItem?.title = "检测人脸: \(count)"
                self?.statusItem.button?.title = "\(count)"
            }
            .store(in: &cancellables)
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Status display (disabled, just informational)
        statusMenuItem = NSMenuItem(title: "状态: 就绪", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(statusMenuItem)

        faceCountMenuItem = NSMenuItem(title: "检测人脸: 0", action: nil, keyEquivalent: "")
        faceCountMenuItem.isEnabled = false
        faceCountMenuItem.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)
        menu.addItem(faceCountMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle monitoring
        toggleMenuItem = NSMenuItem(title: "▶ 开始监控", action: #selector(toggleMonitoring), keyEquivalent: "m")
        toggleMenuItem.target = self
        toggleMenuItem.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        menu.addItem(toggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Show/hide main window
        let windowItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "w")
        windowItem.target = self
        windowItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleMonitoring() {
        guard let controller = controller else { return }
        if controller.isMonitoring {
            controller.stopMonitoring()
        } else {
            controller.startMonitoring()
        }
    }

    @objc private func showMainWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showMainWindow()
        }
    }

    @objc private func quitApp() {
        controller?.stopMonitoring()
        NSApp.terminate(nil)
    }

    // MARK: - Appearance Updates

    private enum IconState: CaseIterable {
        case idle           // gray  – not monitoring
        case calibrating    // yellow – calibrating
        case monitoring     // green  – active & safe
        case threat         // red    – threat detected
    }

    private func updateAppearance(monitoring: Bool, threat: Bool, calibrated: Bool) {
        let state: IconState
        if !monitoring        { state = .idle }
        else if threat        { state = .threat }
        else if !calibrated   { state = .calibrating }
        else                  { state = .monitoring }

        // Use cached icon — no new NSImage allocation on every frame
        statusItem.button?.image = iconCache[state]

        if monitoring {
            toggleMenuItem.title = "■ 停止监控"
            toggleMenuItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        } else {
            toggleMenuItem.title = "▶ 开始监控"
            toggleMenuItem.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        }
    }

    // MARK: - Icon Rendering (called once per state at startup, then results are cached)

    /// Creates a menu bar icon: an eye symbol with a colored state-indicator dot.
    private func makeIcon(state: IconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw eye symbol using an SF Symbol
            if let eyeSymbol = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                let configured = eyeSymbol.withSymbolConfiguration(config) ?? eyeSymbol

                let symbolSize = configured.size
                let x = (rect.width - symbolSize.width) / 2
                let y = (rect.height - symbolSize.height) / 2 + 1.5  // slight upward offset for dot space
                configured.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height))
            }

            // Colored indicator dot at bottom-right
            let dotSize: CGFloat = 5
            let dotRect = NSRect(x: rect.width - dotSize - 1, y: 1, width: dotSize, height: dotSize)

            let dotColor: NSColor
            switch state {
            case .idle:        dotColor = .systemGray
            case .calibrating: dotColor = .systemYellow
            case .monitoring:  dotColor = .systemGreen
            case .threat:      dotColor = .systemRed
            }

            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }

        image.isTemplate = false  // We use color for the dot, so not a pure template
        return image
    }
}
