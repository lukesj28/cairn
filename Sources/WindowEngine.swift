import Cocoa
import ApplicationServices

class WindowEngine {
    static func isTrusted(promptIfNeeded: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
           let subroleStr = subrole as? String {
            return subroleStr == (kAXStandardWindowSubrole as String)
        }
        return false
    }

    static func snapshot() -> [WindowSnapshot] {
        guard isTrusted() else { return [] }
        var snapshots: [WindowSnapshot] = []
        let workspace = NSWorkspace.shared

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName else {
                continue
            }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?

            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                for window in windows {
                    guard isStandardWindow(window) else { continue }
                    
                    var posValue: CFTypeRef?
                    var sizeValue: CFTypeRef?

                    if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
                       AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success {

                        var position = CGPoint.zero
                        var size = CGSize.zero

                        if CFGetTypeID(posValue as CFTypeRef) == AXValueGetTypeID(),
                           CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() {
                            let posAXValue = posValue as! AXValue
                            let sizeAXValue = sizeValue as! AXValue

                            if AXValueGetValue(posAXValue, .cgPoint, &position),
                               AXValueGetValue(sizeAXValue, .cgSize, &size) {
                                let frame = CGRect(origin: position, size: size)
                                snapshots.append(WindowSnapshot(appName: appName, bundleIdentifier: bundleId, frame: frame, displayID: 0))
                            }
                        }
                    }
                }
            }
        }
        return snapshots
    }

    static func restore(profile: Profile) {
        guard isTrusted() else { return }
        let workspace = NSWorkspace.shared

        var bundleIds = Set<String>()
        for w in profile.windows { bundleIds.insert(w.bundleIdentifier) }

        for bundleId in bundleIds {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                workspace.openApplication(at: url, configuration: config) { app, error in
                    if let app = app {
                        ensureWindows(for: app, targetCount: profile.windows.filter { $0.bundleIdentifier == bundleId }.count)
                    }
                }
            }
        }

        // Poll applying window frames
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.sync {
                    self.applyWindowFrames(profile: profile)
                }
            }
        }
    }

    private static func ensureWindows(for app: NSRunningApplication, targetCount: Int) {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        var currentCount = 0

        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            currentCount = windows.filter { isStandardWindow($0) }.count
        }

        if currentCount < targetCount {
            let missing = targetCount - currentCount
            if let bundleId = app.bundleIdentifier {
                let scriptSource = """
                tell application id "\(bundleId)" to activate
                delay 0.2
                tell application "System Events"
                    repeat \(missing) times
                        keystroke "n" using command down
                        delay 0.3
                    end repeat
                end tell
                """
                if let script = NSAppleScript(source: scriptSource) {
                    var errorInfo: NSDictionary?
                    script.executeAndReturnError(&errorInfo)
                }
            }
        }
    }

    private static func applyWindowFrames(profile: Profile) {
        let workspace = NSWorkspace.shared

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { continue }

            let targetWindows = profile.windows.filter { $0.bundleIdentifier == bundleId }
            if targetWindows.isEmpty { continue }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?

            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                
                let standardWindows = windows.filter { isStandardWindow($0) }
                
                for (index, window) in standardWindows.enumerated() {
                    if index < targetWindows.count {
                        let target = targetWindows[index]

                        // Apply exact snapshot frame since bounds-checking corrupted coordinates
                        var position = target.frame.origin
                        var size = target.frame.size

                        if let posValue = AXValueCreate(.cgPoint, &position),
                           let sizeValue = AXValueCreate(.cgSize, &size) {
                            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
                            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                        }
                    }
                }
            }
        }
    }
}
