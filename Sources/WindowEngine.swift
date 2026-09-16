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

    static func snapshot(screens: Int = 1, owningScreen: NSScreen? = nil) -> [WindowSnapshot] {
        guard isTrusted() else { return [] }
        var snapshots: [WindowSnapshot] = []
        let workspace = NSWorkspace.shared
        let visible = Array(ScreenGeometry.axVisibleFrames(owning: owningScreen).prefix(max(1, screens)))

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
                guard frame.width > 1, frame.height > 1 else { continue }

                var matchedIndex = visible.firstIndex(where: { $0.contains(center) })
                if matchedIndex == nil {
                    var maxArea: CGFloat = 0
                    for (i, screenFrame) in visible.enumerated() {
                        let inter = frame.intersection(screenFrame)
                        if !inter.isNull {
                            let area = inter.width * inter.height
                            if area > maxArea {
                                maxArea = area
                                matchedIndex = i
                            }
                        }
                    }
                }
                guard let index = matchedIndex else { continue }

                snapshots.append(WindowSnapshot(appName: appName,
                                                bundleIdentifier: bundleId,
                                                rect: ScreenGeometry.fraction(ofAX: frame, in: visible[index]),
                                                screen: index))
            }
        }
        return snapshots
    }

    static func restore(stack: Stack, owningScreen: NSScreen? = nil) {
        guard isTrusted() else { return }
        let workspace = NSWorkspace.shared
        let visible = ScreenGeometry.axVisibleFrames(owning: owningScreen)
        guard !visible.isEmpty else { return }

        let targets = stack.windows.map { target -> WindowSnapshot in
            if target.screen < visible.count {
                return target
            } else {
                var clamped = target
                clamped.screen = max(0, visible.count - 1)
                return clamped
            }
        }
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
            var placements: [Placement] = []
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.sync {
                    pending = applyWindowFrames(targets: pending, screens: visible, placements: &placements)
                    correctPlacements(&placements)
                }
                if pending.isEmpty && placements.allSatisfy({ $0.settled || $0.attempts >= 5 }) { break }
            }
        }
    }

    private struct Placement {
        let window: AXUIElement
        let target: CGRect
        let screen: CGRect
        var request: CGSize
        var attempts: Int = 1
        var settled: Bool = false
    }

    private static func applyWindowFrames(targets: [WindowSnapshot],
                                          screens: [CGRect],
                                          placements: inout [Placement]) -> [WindowSnapshot] {
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
                for done in placements where CFEqual(done.window, window) { claimed = true }
                if !claimed { free.append(window) }
            }

            var enhancedUI: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, &enhancedUI)
            let wasEnhanced = (enhancedUI as? Bool) ?? false
            if wasEnhanced {
                AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)
            }

            for target in appTargets {
                let targetScreenIndex = min(target.screen, screens.count - 1)
                guard targetScreenIndex >= 0 else {
                    pending.append(target)
                    continue
                }
                let targetScreen = screens[targetScreenIndex]
                let targetAxFrame = rounded(ScreenGeometry.axFrame(ofFraction: target.rect, in: targetScreen))

                guard let window = claim(&free, for: targetAxFrame, on: targetScreen) else {
                    pending.append(target)
                    continue
                }

                setWindowFrame(window, to: targetAxFrame, on: targetScreen, request: targetAxFrame.size)
                placements.append(Placement(window: window,
                                            target: targetAxFrame,
                                            screen: targetScreen,
                                            request: targetAxFrame.size))
            }

            if wasEnhanced {
                AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
            }
        }
        return pending
    }

    private static func setWindowFrame(_ window: AXUIElement, to target: CGRect, on screen: CGRect, request: CGSize) {
        var isFullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &isFullScreen) == .success,
           let fs = isFullScreen as? Bool, fs {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.15)
        }

        var isZoomed: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXZoomed" as CFString, &isZoomed) == .success,
           let z = isZoomed as? Bool, z {
            AXUIElementSetAttributeValue(window, "AXZoomed" as CFString, false as CFTypeRef)
        }

        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let min = isMinimized as? Bool, min {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }

        push(window, size: request, origin: anchor(target: target, size: request, screen: screen))

        if let actual = axFrame(of: window) {
            var origin = anchor(target: target, size: actual.size, screen: screen)
            if let posValue = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            }
        }
    }

    private static func correctPlacements(_ placements: inout [Placement]) {
        for i in placements.indices where !placements[i].settled && placements[i].attempts < 5 {
            let target = placements[i].target
            let screen = placements[i].screen
            guard let actual = axFrame(of: placements[i].window) else { continue }

            let overWidth = actual.width - target.width
            let overHeight = actual.height - target.height
            let wanted = anchor(target: target, size: actual.size, screen: screen)

            if abs(overWidth) <= 1 && abs(overHeight) <= 1
                && abs(actual.minX - wanted.x) <= 1 && abs(actual.minY - wanted.y) <= 1 {
                placements[i].settled = true
                continue
            }

            var request = placements[i].request
            if overWidth > 1 {
                request.width = max(1, request.width - overWidth)
            } else if overWidth < -1 {
                request.width = target.width
            }
            if overHeight > 1 {
                request.height = max(1, request.height - overHeight)
            } else if overHeight < -1 {
                request.height = target.height
            }

            placements[i].request = request
            placements[i].attempts += 1
            setWindowFrame(placements[i].window, to: target, on: screen, request: request)
        }
    }

    private static func rounded(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
    }

    private static func push(_ window: AXUIElement, size: CGSize, origin: CGPoint) {
        var newSize = size
        var newOrigin = origin
        guard let sizeValue = AXValueCreate(.cgSize, &newSize),
              let posValue = AXValueCreate(.cgPoint, &newOrigin) else { return }

        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
    }

    private static func anchor(target: CGRect, size: CGSize, screen: CGRect) -> CGPoint {
        let tolerance: CGFloat = 4
        var x = target.midX - size.width / 2
        if target.minX - screen.minX <= tolerance {
            x = screen.minX
        } else if screen.maxX - target.maxX <= tolerance {
            x = screen.maxX - size.width
        }
        var y = target.midY - size.height / 2
        if target.minY - screen.minY <= tolerance {
            y = screen.minY
        } else if screen.maxY - target.maxY <= tolerance {
            y = screen.maxY - size.height
        }
        if size.width <= screen.width {
            x = min(max(x, screen.minX), screen.maxX - size.width)
        }
        if size.height <= screen.height {
            y = min(max(y, screen.minY), screen.maxY - size.height)
        }
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    private static func claim(_ free: inout [AXUIElement], for targetFrame: CGRect, on screen: CGRect) -> AXUIElement? {
        guard !free.isEmpty else { return nil }

        var bestIndex = 0
        var bestScore = CGFloat.greatestFiniteMagnitude

        for (i, window) in free.enumerated() {
            guard let frame = axFrame(of: window) else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let isOnScreen = screen.contains(center)
            let screenPenalty: CGFloat = isOnScreen ? 0 : 10_000_000
            let dx = frame.midX - targetFrame.midX
            let dy = frame.midY - targetFrame.midY
            let score = screenPenalty + (dx * dx + dy * dy)
            if score < bestScore {
                bestScore = score
                bestIndex = i
            }
        }
        return free.remove(at: bestIndex)
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
