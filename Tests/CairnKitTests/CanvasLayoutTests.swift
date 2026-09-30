import Testing
import CoreGraphics
@testable import CairnKit

@Suite("Canvas layout")
struct CanvasLayoutTests {
    @Test("one canvas fills the width it is given")
    func oneCanvasFillsWidth() {
        let rects = CanvasLayout.rects(in: CGSize(width: 600, height: 400), aspects: [1.5], spacing: 8)
        #expect(rects.count == 1)
        #expect(isClose(rects[0], CGRect(x: 0, y: 0, width: 600, height: 400)))
    }

    @Test("two canvases share the height")
    func twoCanvasesShareHeight() {
        let rects = CanvasLayout.rects(in: CGSize(width: 600, height: 400), aspects: [1.5, 1.5], spacing: 8)
        #expect(rects.count == 2)
        #expect(isClose(rects[0], CGRect(x: 153, y: 0, width: 294, height: 196)))
        #expect(isClose(rects[1], CGRect(x: 153, y: 204, width: 294, height: 196)))
    }

    @Test("two canvases have identical size even when input aspects differ")
    func twoCanvasesHaveIdenticalSize() {
        let rects = CanvasLayout.rects(in: CGSize(width: 600, height: 400), aspects: [1.6, 1.777], spacing: 8)
        #expect(rects.count == 2)
        #expect(isClose(rects[0].width, rects[1].width))
        #expect(isClose(rects[0].height, rects[1].height))
    }

    @Test("a canvas never exceeds the available width")
    func canvasNeverExceedsWidth() {
        let rects = CanvasLayout.rects(in: CGSize(width: 200, height: 1000), aspects: [1.5], spacing: 8)
        #expect(rects.count == 1)
        #expect(isClose(rects[0].width, 200))
    }

    @Test("no aspects, no canvases")
    func noAspectsNoCanvases() {
        #expect(CanvasLayout.rects(in: CGSize(width: 600, height: 400), aspects: [], spacing: 8).isEmpty)
    }
}
