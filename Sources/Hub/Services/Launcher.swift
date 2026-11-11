import AppKit

@MainActor
enum Launcher {
    private static var iconCache: [String: NSImage] = [:]

    static func appURL(_ bundleIDs: [String]) -> URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return nil
    }

    static func isInstalled(_ bundleIDs: [String]) -> Bool { appURL(bundleIDs) != nil }

    static func runningApp(_ bundleIDs: [String]) -> NSRunningApplication? {
        for id in bundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return app }
        }
        return nil
    }

    static func icon(_ bundleIDs: [String]) -> NSImage? {
        guard let key = bundleIDs.first else { return nil }
        if let cached = iconCache[key] { return cached }
        guard let url = appURL(bundleIDs) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[key] = icon
        return icon
    }

    /// Uygulamayı açar; açıldıysa true döner.
    @discardableResult
    static func launch(_ bundleIDs: [String]) -> Bool {
        if let running = runningApp(bundleIDs) {
            running.unhide()
            running.activate()
            // Penceresi kapalıysa yeniden açılması için uygulamayı tekrar "aç".
            if let url = running.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
            return true
        }
        guard let url = appURL(bundleIDs) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
