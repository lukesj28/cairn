import AppKit

@main
enum GeometryChecks {
    static func main() {
        roundTripPreservesRatios()
        clampKeepsRectsOnScreen()
        dropAssignsCanvasAndFraction()
        print("geometry checks passed")
    }

    private static func roundTripPreservesRatios() {
        let wide = CGRect(x: -1920, y: -283, width: 1920, height: 1050)
        let narrow = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let sixth = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 1.0 / 3.0)

        let onWide = ScreenGeometry.axFrame(ofFraction: sixth, in: wide)
        let backToFraction = ScreenGeometry.fraction(ofAX: onWide, in: wide)
        assert(close(backToFraction, sixth), "round trip lost the fraction: \(backToFraction)")

        let onNarrow = ScreenGeometry.axFrame(ofFraction: sixth, in: narrow)
        let wideShare = (onWide.width * onWide.height) / (wide.width * wide.height)
        let narrowShare = (onNarrow.width * onNarrow.height) / (narrow.width * narrow.height)
        assert(abs(wideShare - 1.0 / 6.0) < 1e-9, "wide screen area share \(wideShare)")
        assert(abs(narrowShare - wideShare) < 1e-9, "area share changed across screens: \(narrowShare)")

        assert(onNarrow.minX >= narrow.minX - 1e-9, "left edge escaped the screen")
        assert(onNarrow.maxY <= narrow.maxY + 1e-9, "bottom edge escaped the screen")
    }

    private static func clampKeepsRectsOnScreen() {
        let overflowing = ScreenGeometry.clamp(CGRect(x: 0.95, y: 0.95, width: 0.2, height: 0.001))
        assert(overflowing.maxX <= 1 + 1e-9 && overflowing.maxY <= 1 + 1e-9, "clamp left the screen: \(overflowing)")
        assert(overflowing.height >= ScreenGeometry.minFraction, "clamp allowed an invisible tile")

        let offscreen = ScreenGeometry.fraction(ofAX: CGRect(x: -1920, y: -283, width: 640, height: 525),
                                                in: CGRect(x: 0, y: 33, width: 1512, height: 949))
        assert(offscreen.minX >= 0 && offscreen.minY >= 0, "negative fraction survived: \(offscreen)")
        assert(offscreen.maxX <= 1 + 1e-9 && offscreen.maxY <= 1 + 1e-9, "fraction exceeded the screen: \(offscreen)")
    }

    private static func dropAssignsCanvasAndFraction() {
        let canvases = [0: CGRect(x: 0, y: 0, width: 400, height: 250),
                        1: CGRect(x: 0, y: 262, width: 400, height: 225)]
        let tile = CGRect(x: 100, y: 100, width: 100, height: 50)

        guard let stay = ScreenGeometry.drop(tile, from: 0, canvases: canvases) else {
            fatalError("drop returned nil for its own canvas")
        }
        assert(stay.screen == 0, "tile changed screen without moving")
        assert(close(stay.rect, CGRect(x: 0.25, y: 0.4, width: 0.25, height: 0.2)), "same canvas fraction \(stay.rect)")

        guard let moved = ScreenGeometry.drop(tile.offsetBy(dx: 0, dy: 200), from: 0, canvases: canvases) else {
            fatalError("drop returned nil across canvases")
        }
        assert(moved.screen == 1, "tile dropped on the second canvas kept screen 0")
        assert(abs(moved.rect.minY - (300 - 262) / 225) < 1e-9, "cross canvas fraction \(moved.rect)")

        guard let gap = ScreenGeometry.drop(tile.offsetBy(dx: 0, dy: 130), from: 0, canvases: canvases) else {
            fatalError("drop returned nil in the gap")
        }
        assert(gap.screen == 0, "tile dropped between canvases changed screen")
        assert(gap.rect.maxY <= 1 + 1e-9, "gap drop escaped the canvas: \(gap.rect)")

        assert(ScreenGeometry.drop(tile, from: 7, canvases: canvases) == nil, "drop accepted an unknown canvas")
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
            && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    }
}
