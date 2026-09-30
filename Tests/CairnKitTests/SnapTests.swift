import Testing
import CoreGraphics
@testable import CairnKit

@Suite("Snapping")
struct SnapTests {
    @Test("a moved tile lands on the grid")
    func movedTileLandsOnGrid() {
        let result = SnapGrid.snapMove(CGRect(x: 0.26, y: 0.13, width: 0.5, height: 0.25), neighbours: [])
        #expect(isClose(result, CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.25)))
    }

    @Test("a tile near a neighbour goes flush")
    func tileNearNeighbourGoesFlush() {
        let neighbour = CGRect(x: 0, y: 0, width: 0.53, height: 1)
        let moved = CGRect(x: 0.545, y: 0, width: 0.4, height: 1)
        let result = SnapGrid.snapMove(moved, neighbours: [neighbour])
        #expect(isClose(result.minX, 0.53))
    }

    @Test("the trailing edge snaps to the screen edge")
    func trailingEdgeSnapsToScreenEdge() {
        let a = SnapGrid.snapMove(CGRect(x: 0.487, y: 0, width: 0.5, height: 1), neighbours: [])
        #expect(isClose(a.minX, 0.5))

        let b = SnapGrid.snapMove(CGRect(x: 0.995, y: 0, width: 0.5, height: 0.5), neighbours: [])
        #expect(b.maxX <= 1)
    }

    @Test("resizing snaps the far edge and keeps the origin")
    func resizingSnapsFarEdge() {
        let result = SnapGrid.snapResize(CGRect(x: 0.25, y: 0.125, width: 0.29, height: 0.30), neighbours: [])
        #expect(isClose(result, CGRect(x: 0.25, y: 0.125, width: 0.25, height: 0.25)))
    }

    @Test("a resized tile never collapses")
    func resizedTileNeverCollapses() {
        let result = SnapGrid.snapResize(CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001), neighbours: [])
        #expect(result.width >= 1.0 / 12 - 1e-9)
        #expect(result.height >= 1.0 / 8 - 1e-9)
        #expect(result.minX >= 0 && result.maxX <= 1)
        #expect(result.minY >= 0 && result.maxY <= 1)
    }

    @Test("resizing trailing edge to workable area edge stops and keeps origin")
    func resizingTrailingEdgeStopsAtEdge() {
        let original = CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.5)
        let dragged = CGRect(x: 0.25, y: 0.125, width: 0.95, height: 0.5)
        let snapped = SnapGrid.snapResize(rect: dragged, original: original, neighbours: [])
        #expect(isClose(snapped.minX, 0.25))
        #expect(isClose(snapped.maxX, 1.0))

        let clamped = SnapGrid.clampResize(rect: dragged, original: original)
        #expect(isClose(clamped.minX, 0.25))
        #expect(isClose(clamped.maxX, 1.0))
    }

    @Test("resizing leading edge to workable area edge stops and keeps far edge")
    func resizingLeadingEdgeStopsAtEdge() {
        let original = CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.5)
        let dragged = CGRect(x: -0.2, y: 0.125, width: 0.95, height: 0.5)
        let snapped = SnapGrid.snapResize(rect: dragged, original: original, neighbours: [])
        #expect(isClose(snapped.minX, 0.0))
        #expect(isClose(snapped.maxX, 0.75))

        let clamped = SnapGrid.clampResize(rect: dragged, original: original)
        #expect(isClose(clamped.minX, 0.0))
        #expect(isClose(clamped.maxX, 0.75))
    }

    @Test("resizing bottom edge to workable area edge stops and keeps top edge")
    func resizingBottomEdgeStopsAtEdge() {
        let original = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let dragged = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.95)
        let snapped = SnapGrid.snapResize(rect: dragged, original: original, neighbours: [])
        #expect(isClose(snapped.minY, 0.25))
        #expect(isClose(snapped.maxY, 1.0))

        let clamped = SnapGrid.clampResize(rect: dragged, original: original)
        #expect(isClose(clamped.minY, 0.25))
        #expect(isClose(clamped.maxY, 1.0))
    }

    @Test("resizing top edge to workable area edge stops and keeps bottom edge")
    func resizingTopEdgeStopsAtEdge() {
        let original = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let dragged = CGRect(x: 0.25, y: -0.3, width: 0.5, height: 1.05)
        let snapped = SnapGrid.snapResize(rect: dragged, original: original, neighbours: [])
        #expect(isClose(snapped.minY, 0.0))
        #expect(isClose(snapped.maxY, 0.75))

        let clamped = SnapGrid.clampResize(rect: dragged, original: original)
        #expect(isClose(clamped.minY, 0.0))
        #expect(isClose(clamped.maxY, 0.75))
    }
}
