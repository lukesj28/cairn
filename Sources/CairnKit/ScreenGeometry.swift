import AppKit

public enum ScreenGeometry {
    public static func owningScreen() -> NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func orderedScreens(owning: NSScreen? = nil) -> [NSScreen] {
        let all = NSScreen.screens
        guard let active = owning ?? owningScreen() ?? all.first else { return [] }
        return [active] + all.filter { $0 !== active }.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static var axTop: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }

    private static func menuBarRects() -> [CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuBarLevel = CGWindowLevelForKey(.mainMenuWindow)
        return list.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int32 == menuBarLevel,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(x: bounds["X"] as? CGFloat ?? 0,
                          y: bounds["Y"] as? CGFloat ?? 0,
                          width: bounds["Width"] as? CGFloat ?? 0,
                          height: bounds["Height"] as? CGFloat ?? 0)
        }
    }

    private static func axVisibleFrame(of screen: NSScreen, menuBars: [CGRect]) -> CGRect {
        let vf = screen.visibleFrame
        var axRect = CGRect(x: vf.minX, y: axTop - vf.maxY, width: vf.width, height: vf.height)

        for menuBar in menuBars {
            let strip = CGRect(x: axRect.minX, y: axRect.minY, width: axRect.width, height: menuBar.height + 5)
            guard menuBar.intersects(strip) else { continue }
            let overlap = menuBar.maxY - axRect.minY
            if overlap > 0 && overlap < 100 {
                axRect.origin.y += overlap
                axRect.size.height -= overlap
            }
        }
        return axRect
    }

    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        axVisibleFrame(of: screen, menuBars: menuBarRects())
    }

    static func axVisibleFrames(owning: NSScreen? = nil) -> [CGRect] {
        let menuBars = menuBarRects()
        return orderedScreens(owning: owning).map { axVisibleFrame(of: $0, menuBars: menuBars) }
    }

    static func axVisibleFrame(ofScreen index: Int, owning: NSScreen? = nil) -> CGRect? {
        let frames = axVisibleFrames(owning: owning)
        return index < frames.count ? frames[index] : nil
    }

    static var activeVisibleFrame: CGRect {
        axVisibleFrame(ofScreen: 0) ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    }

    public static func aspectRatio(ofScreen index: Int, owning: NSScreen? = nil) -> CGFloat {
        let r = axVisibleFrame(ofScreen: index, owning: owning) ?? activeVisibleFrame
        return r.height > 0 ? r.width / r.height : 16.0 / 9.0
    }

    static let minFraction: CGFloat = 0.05

    public static func clamp(_ r: CGRect) -> CGRect {
        guard r.minX.isFinite, r.minY.isFinite, r.width.isFinite, r.height.isFinite else {
            return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        }
        let w = min(1, max(minFraction, r.width))
        let h = min(1, max(minFraction, r.height))
        return CGRect(x: min(max(0, r.minX), 1 - w),
                      y: min(max(0, r.minY), 1 - h),
                      width: w, height: h)
    }

    static func fraction(ofAX frame: CGRect, in visible: CGRect) -> CGRect {
        guard visible.width > 0, visible.height > 0 else { return clamp(.zero) }
        return clamp(CGRect(x: (frame.minX - visible.minX) / visible.width,
                            y: (frame.minY - visible.minY) / visible.height,
                            width: frame.width / visible.width,
                            height: frame.height / visible.height))
    }

    static func axFrame(ofFraction r: CGRect, in visible: CGRect) -> CGRect {
        CGRect(x: visible.minX + r.minX * visible.width,
               y: visible.minY + r.minY * visible.height,
               width: r.width * visible.width,
               height: r.height * visible.height)
    }

    public static func drop(_ box: CGRect, from index: Int, canvases: [Int: CGRect]) -> (screen: Int, rect: CGRect)? {
        guard let source = canvases[index] else { return nil }
        let global = box.offsetBy(dx: source.minX, dy: source.minY)
        let centre = CGPoint(x: global.midX, y: global.midY)
        let screen = canvases.first { $0.value.contains(centre) }?.key ?? index
        guard let canvas = canvases[screen], canvas.width > 0, canvas.height > 0 else { return nil }
        let local = global.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        return (screen, clamp(CGRect(x: local.minX / canvas.width,
                                     y: local.minY / canvas.height,
                                     width: local.width / canvas.width,
                                     height: local.height / canvas.height)))
    }
}
