import Testing
import CoreGraphics
@testable import CairnKit

func isClose(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-9) -> Bool { abs(a - b) <= tolerance }
func isClose(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-9) -> Bool {
    isClose(a.minX, b.minX, tolerance) && isClose(a.minY, b.minY, tolerance)
        && isClose(a.width, b.width, tolerance) && isClose(a.height, b.height, tolerance)
}

@Suite("Screen geometry")
struct GeometryTests {
    @Test("a fraction survives a round trip through AX coordinates")
    func roundTrip() {
        let sixth = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 1.0 / 3.0)
        let onExternal = ScreenGeometry.axFrame(ofFraction: sixth, in: externalVisible)
        let back = ScreenGeometry.fraction(ofAX: onExternal, in: externalVisible)
        #expect(isClose(back, sixth))
    }

    @Test("the same fraction occupies the same share of any screen")
    func areaShare() {
        let sixth = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 1.0 / 3.0)
        let onExternal = ScreenGeometry.axFrame(ofFraction: sixth, in: externalVisible)
        let onLaptop = ScreenGeometry.axFrame(ofFraction: sixth, in: laptopVisible)
        let externalShare = (onExternal.width * onExternal.height) / (externalVisible.width * externalVisible.height)
        let laptopShare = (onLaptop.width * onLaptop.height) / (laptopVisible.width * laptopVisible.height)
        #expect(isClose(externalShare, 1.0 / 6.0))
        #expect(isClose(laptopShare, externalShare))
    }

    @Test("a window saved on another display is pulled onto this one")
    func crossDisplay() {
        let fraction = ScreenGeometry.fraction(ofAX: CGRect(x: -1920, y: -283, width: 640, height: 525),
                                               in: laptopVisible)
        #expect(fraction.minX == 0)
        #expect(fraction.minY == 0)
        #expect(isClose(fraction.width, 640.0 / 1512.0))
        #expect(isClose(fraction.height, 525.0 / 949.0))
    }

    @Test("clamp keeps a tile on screen and above the minimum")
    func clampOnScreen() {
        let result = ScreenGeometry.clamp(CGRect(x: 0.95, y: 0.95, width: 0.2, height: 0.001))
        #expect(isClose(result, CGRect(x: 0.8, y: 0.95, width: 0.2, height: 0.05)))
    }

    @Test("clamp shrinks a tile that is larger than the screen")
    func clampOversized() {
        let result = ScreenGeometry.clamp(CGRect(x: 0.2, y: 0.2, width: 2, height: 3))
        #expect(isClose(result, CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    @Test("clamp repairs a rect that is not a number", arguments: [
        CGRect(x: .nan, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0, y: 0, width: .infinity, height: 0.5),
        CGRect(x: 0, y: .nan, width: 0.5, height: .nan),
    ])
    func clampNonFinite(_ input: CGRect) {
        let result = ScreenGeometry.clamp(input)
        #expect(isClose(result, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
    }

    @Test("a tile dropped on its own canvas keeps its screen")
    func dropSameCanvas() throws {
        let tile = CGRect(x: 100, y: 100, width: 100, height: 50)
        let stay = try #require(ScreenGeometry.drop(tile, from: 0, canvases: dropCanvases))
        #expect(stay.screen == 0)
        #expect(isClose(stay.rect, CGRect(x: 0.25, y: 0.4, width: 0.25, height: 0.2)))
    }

    @Test("a tile dropped on the other canvas switches screen")
    func dropOtherCanvas() throws {
        let tile = CGRect(x: 100, y: 100, width: 100, height: 50)
        let moved = try #require(ScreenGeometry.drop(tile.offsetBy(dx: 0, dy: 200), from: 0, canvases: dropCanvases))
        #expect(moved.screen == 1)
        #expect(isClose(moved.rect.minY, (300 - 262) / 225))
    }

    @Test("a tile dropped between canvases stays put")
    func dropInGap() throws {
        let tile = CGRect(x: 100, y: 100, width: 100, height: 50)
        let gap = try #require(ScreenGeometry.drop(tile.offsetBy(dx: 0, dy: 130), from: 0, canvases: dropCanvases))
        #expect(gap.screen == 0)
        #expect(gap.rect.maxY <= 1 + 1e-9)
    }

    @Test("a tile from an unknown canvas is rejected")
    func dropUnknownCanvas() {
        let tile = CGRect(x: 100, y: 100, width: 100, height: 50)
        #expect(ScreenGeometry.drop(tile, from: 7, canvases: dropCanvases) == nil)
    }
}

private let dropCanvases = [0: CGRect(x: 0, y: 0, width: 400, height: 250),
                            1: CGRect(x: 0, y: 262, width: 400, height: 225)]
