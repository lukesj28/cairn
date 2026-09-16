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

    static func snapshot(screens: Int = 1) -> [WindowSnapshot] {
        guard isTrusted() else { return [] }
        var snapshots: [WindowSnapshot] = []
        let workspace = NSWorkspace.shared
        let visible = Array(ScreenGeometry.axVisibleFrames().prefix(max(1, screens)))

        for app in workspace.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName else {
                continue
            }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?

            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for window in windows {
                guard isStandardWindow(window) else { continue }

                var posValue: CFTypeRef?
                var sizeValue: CFTypeRef?

                guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
                      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                      CFGetTypeID(posValue as CFTypeRef) == AXValueGetTypeID(),
                      CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else { continue }

                var position = CGPoint.zero
                var size = CGSize.zero

                guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { continue }

                let frame = CGRect(origin: position, size: size)
                let center = CGPoint(x: frame.midX, y: frame.midY)
                guard frame.width > 1, frame.height > 1,
                      let index = visible.firstIndex(where: { $0.contains(center) }) else { continue }

                snapshots.append(WindowSnapshot(appName: appName,
                                                bundleIdentifier: bundleId,
                                                rect: ScreenGeometry.fraction(ofAX: frame, in: visible[index]),
                                                screen: index))
            }
        }
        return snapshots
    }

    static func restore(stack: Stack) {
        guard isTrusted() else { return }
        let workspace = NSWorkspace.shared
        let visible = ScreenGeometry.axVisibleFrames()

        let targets = stack.windows.filter { $0.screen < visible.count }
        guard !targets.isEmpty else { return }

        for bundleId in Set(targets.map { $0.bundleIdentifier }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                workspace.openApplication(at: url, configuration: config, completionHandler: nil)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var pending = targets
            var placed: [AXUIElement] = []
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.sync {
                    pending = applyWindowFrames(targets: pending, screens: visible, placed: &placed)
                }
                if pending.isEmpty { break }
            }
        }
    }

    private static func applyWindowFrames(targets: [WindowSnapshot],
                                          screens: [CGRect],
                                          placed: inout [AXUIElement]) -> [WindowSnapshot] {
        var pending: [WindowSnapshot] = []

        for (bundleId, appTargets) in Dictionary(grouping: targets, by: { $0.bundleIdentifier }) {
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular && $0.bundleIdentifier == bundleId
            }) else {
                pending.append(contentsOf: appTargets)
                continue
            }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else {
                pending.append(contentsOf: appTargets)
                continue
            }

            var free: [AXUIElement] = []
            for window in windows where isStandardWindow(window) {
                var claimed = false
                for done in placed where CFEqual(done, window) { claimed = true }
                if !claimed { free.append(window) }
            }

            for target in appTargets {
                guard target.screen < screens.count,
                      let pick = claim(&free, on: screens[target.screen]) else {
                    pending.append(target)
                    continue
                }
                let window = pick
                let ax = ScreenGeometry.axFrame(ofFraction: target.rect, in: screens[target.screen])
                var position = ax.origin
                var size = ax.size

                if let posValue = AXValueCreate(.cgPoint, &position),
                   let sizeValue = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
                }
                placed.append(window)
            }
        }
        return pending
    }

    private static func claim(_ free: inout [AXUIElement], on screen: CGRect) -> AXUIElement? {
        guard !free.isEmpty else { return nil }
        let local = free.firstIndex { window in
            guard let frame = axFrame(of: window) else { return false }
            return screen.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        return free.remove(at: local ?? 0)
    }

    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              CFGetTypeID(posValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
