import AppKit

enum ScreenGeometry {
    static func owningScreen() -> NSScreen? {
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

    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var axRect = CGRect(x: vf.minX, y: axTop - vf.maxY, width: vf.width, height: vf.height)

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let name = w[kCGWindowName as String] as? String ?? ""
            if layer == 24, name == "Menubar", let b = w[kCGWindowBounds as String] as? [String: Any] {
                let mbX = b["X"] as? CGFloat ?? 0
                let mbY = b["Y"] as? CGFloat ?? 0
                let mbW = b["Width"] as? CGFloat ?? 0
                let mbH = b["Height"] as? CGFloat ?? 0
                let mbRect = CGRect(x: mbX, y: mbY, width: mbW, height: mbH)

                if mbRect.intersects(CGRect(x: axRect.minX, y: axRect.minY, width: axRect.width, height: mbH + 5)) {
                    let diff = mbRect.maxY - axRect.minY
                    if diff > 0 && diff < 100 {
                        axRect.origin.y += diff
                        axRect.size.height -= diff
                    }
                }
            }
        }
        return axRect
    }

    static func axVisibleFrames(owning: NSScreen? = nil) -> [CGRect] {
        orderedScreens(owning: owning).map(axVisibleFrame(of:))
    }

    static func axVisibleFrame(ofScreen index: Int, owning: NSScreen? = nil) -> CGRect? {
        let frames = axVisibleFrames(owning: owning)
        return index < frames.count ? frames[index] : nil
    }

    static var activeVisibleFrame: CGRect {
        axVisibleFrame(ofScreen: 0) ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    }

    static func aspectRatio(ofScreen index: Int, owning: NSScreen? = nil) -> CGFloat {
        let r = axVisibleFrame(ofScreen: index, owning: owning) ?? activeVisibleFrame
        return r.height > 0 ? r.width / r.height : 16.0 / 9.0
    }

    static let minFraction: CGFloat = 0.05

    static func clamp(_ r: CGRect) -> CGRect {
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

    static func drop(_ box: CGRect, from index: Int, canvases: [Int: CGRect]) -> (screen: Int, rect: CGRect)? {
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
