import Cocoa
import ApplicationServices

public enum WindowEngine {
    private static let placementQueue = DispatchQueue(label: "com.lucassanjuan.Cairn.placement")

    public static func isTrusted(promptIfNeeded: Bool = true) -> Bool {
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

    private static func processIDs(for bundleIDs: Set<String>) -> [String: pid_t] {
        var result: [String: pid_t] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  bundleIDs.contains(bundleId),
                  result[bundleId] == nil else { continue }
            result[bundleId] = app.processIdentifier
        }
        return result
    }

    public static func snapshot(screens: Int = 1,
                                owningScreen: NSScreen? = nil,
                                completion: @escaping ([WindowSnapshot]) -> Void) {
        guard isTrusted() else { completion([]); return }
        let visible = Array(ScreenGeometry.axVisibleFrames(owning: owningScreen).prefix(max(1, screens)))
        let apps: [(pid: pid_t, bundleID: String, name: String)] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName else { return nil }
            return (app.processIdentifier, bundleId, appName)
        }

        placementQueue.async {
            let result = scan(apps: apps, visible: visible)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func scan(apps: [(pid: pid_t, bundleID: String, name: String)], visible: [CGRect]) -> [WindowSnapshot] {
        var snapshots: [WindowSnapshot] = []

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.pid)
            var value: CFTypeRef?

            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for window in windows {
                guard isStandardWindow(window) else { continue }

                guard let frame = axFrame(of: window), frame.width > 1, frame.height > 1 else { continue }
                let center = CGPoint(x: frame.midX, y: frame.midY)

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

                snapshots.append(WindowSnapshot(appName: app.name,
                                                bundleIdentifier: app.bundleID,
                                                rect: ScreenGeometry.fraction(ofAX: frame, in: visible[index]),
                                                screen: index))
            }
        }
        return snapshots
    }

    public static func open(stack: Stack, owningScreen: NSScreen? = nil) {
        guard isTrusted() else { return }
        let workspace = NSWorkspace.shared
        let visible = ScreenGeometry.axVisibleFrames(owning: owningScreen)
        guard !visible.isEmpty else { return }

        let targets = stack.windows.map { window -> WindowSnapshot in
            var target = window
            target.screen = screenIndex(for: window, screenCount: visible.count)
            return target
        }
        guard !targets.isEmpty else { return }

        for bundleId in Set(targets.map { $0.bundleIdentifier }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                workspace.openApplication(at: url, configuration: config, completionHandler: nil)
            }
        }

        placementQueue.async {
            var pending = targets
            var placements: [Placement] = []
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.5)
                let bundleIDs = Set(pending.map { $0.bundleIdentifier })
                    .union(placements.isEmpty ? [] : Set(targets.map { $0.bundleIdentifier }))
                let pids = DispatchQueue.main.sync { processIDs(for: bundleIDs) }
                pending = applyWindowFrames(targets: pending, screens: visible, pids: pids, placements: &placements)
                correctPlacements(&placements)
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
                                          pids: [String: pid_t],
                                          placements: inout [Placement]) -> [WindowSnapshot] {
        var pending: [WindowSnapshot] = []

        for (bundleId, appTargets) in Dictionary(grouping: targets, by: { $0.bundleIdentifier }) {
            guard let pid = pids[bundleId] else {
                pending.append(contentsOf: appTargets)
                continue
            }

            let axApp = AXUIElementCreateApplication(pid)
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
                let targetScreenIndex = screenIndex(for: target, screenCount: screens.count)
                guard screens.indices.contains(targetScreenIndex) else {
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
           let fullScreen = isFullScreen as? Bool, fullScreen {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.15)
        }

        var isZoomed: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXZoomed" as CFString, &isZoomed) == .success,
           let zoomed = isZoomed as? Bool, zoomed {
            AXUIElementSetAttributeValue(window, "AXZoomed" as CFString, false as CFTypeRef)
        }

        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool, minimized {
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
            guard let actual = axFrame(of: placements[i].window) else { continue }
            let outcome = negotiate(target: placements[i].target,
                                    actual: actual,
                                    request: placements[i].request,
                                    screen: placements[i].screen)
            if outcome.settled {
                placements[i].settled = true
                continue
            }
            placements[i].request = outcome.request
            placements[i].attempts += 1
            setWindowFrame(placements[i].window,
                           to: placements[i].target,
                           on: placements[i].screen,
                           request: outcome.request)
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

    static func anchor(target: CGRect, size: CGSize, screen: CGRect) -> CGPoint {
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
        if size.width > screen.width {
            x = screen.minX
        } else {
            x = min(max(x, screen.minX), screen.maxX - size.width)
        }
        if size.height > screen.height {
            y = screen.minY
        } else {
            y = min(max(y, screen.minY), screen.maxY - size.height)
        }
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    static func screenIndex(for window: WindowSnapshot, screenCount: Int) -> Int {
        guard screenCount > 0 else { return 0 }
        return min(max(0, window.screen), screenCount - 1)
    }

    static func negotiate(target: CGRect,
                          actual: CGRect,
                          request: CGSize,
                          screen: CGRect) -> (settled: Bool, request: CGSize) {
        let overWidth = actual.width - target.width
        let overHeight = actual.height - target.height
        let wanted = anchor(target: target, size: actual.size, screen: screen)

        if abs(overWidth) <= 1 && abs(overHeight) <= 1
            && abs(actual.minX - wanted.x) <= 1 && abs(actual.minY - wanted.y) <= 1 {
            return (true, request)
        }

        var next = request
        if overWidth > 1 {
            next.width = max(1, request.width - overWidth)
        } else if overWidth < -1 {
            next.width = target.width
        }
        if overHeight > 1 {
            next.height = max(1, request.height - overHeight)
        } else if overHeight < -1 {
            next.height = target.height
        }
        return (false, next)
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
              let position = posValue, CFGetTypeID(position) == AXValueGetTypeID(),
              let size = sizeValue, CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
