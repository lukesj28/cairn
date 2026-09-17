import AppKit

enum AppIcon {
    private static var cache: [String: NSImage?] = [:]

    static func image(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = icon
        return icon
    }
}
