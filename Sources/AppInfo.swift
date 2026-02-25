import AppKit
import Foundation

/// Represents an installed application for use in the whitelist / target picker.
struct AppInfo: Identifiable, Codable, Hashable {
    /// Bundle identifier, e.g. "com.microsoft.VSCode"
    let bundleId: String
    /// Display name, e.g. "Visual Studio Code"
    let name: String

    var id: String { bundleId }

    // MARK: - Icon (non-codable, computed on demand)

    /// Returns the app's icon from its bundle, or a generic app icon.
    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    // MARK: - Discovery

    /// Returns a list of commonly-installed GUI apps on the system.
    static func installedApps() -> [AppInfo] {
        var results: [String: AppInfo] = [:]  // keyed by bundleId to deduplicate

        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]

        let fm = FileManager.default

        for dir in searchPaths {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                if let bundle = Bundle(path: fullPath),
                   let bid = bundle.bundleIdentifier {
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? (item as NSString).deletingPathExtension
                    results[bid] = AppInfo(bundleId: bid, name: name)
                }
            }
        }

        return results.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns a list of currently running GUI applications.
    static func runningApps() -> [AppInfo] {
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bid = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return AppInfo(bundleId: bid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
