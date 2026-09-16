import AppKit

enum ScreenGeometry {
    static func orderedScreens() -> [NSScreen] {
        let all = NSScreen.screens
        guard let active = NSScreen.main ?? all.first else { return [] }
        return [active] + all.filter { $0 !== active }.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static var axTop: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.maxY ?? 0
    }

    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        return CGRect(x: vf.minX, y: axTop - vf.maxY, width: vf.width, height: vf.height)
    }

    static func axVisibleFrames() -> [CGRect] { orderedScreens().map(axVisibleFrame(of:)) }

    static func axVisibleFrame(ofScreen index: Int) -> CGRect? {
        let frames = axVisibleFrames()
        return index < frames.count ? frames[index] : nil
    }

    static var activeVisibleFrame: CGRect {
        axVisibleFrame(ofScreen: 0) ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    }

    static func aspectRatio(ofScreen index: Int) -> CGFloat {
        let r = axVisibleFrame(ofScreen: index) ?? activeVisibleFrame
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
