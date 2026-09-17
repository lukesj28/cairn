import Testing
import CoreGraphics
@testable import CairnKit

let laptopVisible = CGRect(x: 0, y: 33, width: 1512, height: 949)
let externalVisible = CGRect(x: -1920, y: -283, width: 1920, height: 1050)

@Suite("Window placement")
struct PlacementTests {
    @Test("a flush edge stays flush when the app returns a bigger window")
    func flushLeftStaysFlush() {
        let point = WindowEngine.anchor(target: CGRect(x: 0, y: 33, width: 756, height: 949),
                                        size: CGSize(width: 790, height: 920),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 0, y: 33))
    }

    @Test("a right-flush window is right-aligned")
    func flushRight() {
        let point = WindowEngine.anchor(target: CGRect(x: 756, y: 33, width: 756, height: 949),
                                        size: CGSize(width: 700, height: 949),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 812, y: 33))
    }

    @Test("a bottom-flush window is bottom-aligned")
    func flushBottom() {
        let point = WindowEngine.anchor(target: CGRect(x: 0, y: 782, width: 300, height: 200),
                                        size: CGSize(width: 300, height: 180),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 0, y: 802))
    }

    @Test("an interior window keeps its centre")
    func interiorCentered() {
        let point = WindowEngine.anchor(target: CGRect(x: 400, y: 300, width: 200, height: 200),
                                        size: CGSize(width: 220, height: 180),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 390, y: 310))
    }

    @Test("an interior window is pulled back inside the screen")
    func interiorPulledBack() {
        let point = WindowEngine.anchor(target: CGRect(x: 1300, y: 33, width: 200, height: 200),
                                        size: CGSize(width: 400, height: 200),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 1112, y: 33))
    }

    @Test("a window larger than the screen starts at the screen corner")
    func largerThanScreen() {
        let point = WindowEngine.anchor(target: CGRect(x: 400, y: 300, width: 200, height: 200),
                                        size: CGSize(width: 1600, height: 1200),
                                        screen: laptopVisible)
        #expect(point == CGPoint(x: 0, y: 33))
    }

    @Test("an over-wide window is negotiated down to its slot")
    func negotiateOverWide() {
        let outcome = WindowEngine.negotiate(target: CGRect(x: 0, y: 33, width: 756, height: 949),
                                             actual: CGRect(x: 0, y: 33, width: 790, height: 920),
                                             request: CGSize(width: 756, height: 949),
                                             screen: laptopVisible)
        #expect(outcome.settled == false)
        #expect(outcome.request == CGSize(width: 722, height: 949))
    }

    @Test("an exact match settles")
    func negotiateExactMatch() {
        let rect = CGRect(x: 756, y: 33, width: 756, height: 949)
        let outcome = WindowEngine.negotiate(target: rect, actual: rect,
                                             request: CGSize(width: 756, height: 949),
                                             screen: laptopVisible)
        #expect(outcome.settled == true)
        #expect(outcome.request == CGSize(width: 756, height: 949))
    }

    @Test("the right size at the wrong place is not settled")
    func negotiateWrongPlace() {
        let target = CGRect(x: 756, y: 33, width: 756, height: 949)
        let actual = CGRect(x: 100, y: 33, width: 756, height: 949)
        let outcome = WindowEngine.negotiate(target: target, actual: actual,
                                             request: CGSize(width: 756, height: 949),
                                             screen: laptopVisible)
        #expect(outcome.settled == false)
        #expect(outcome.request == CGSize(width: 756, height: 949))
    }

    @Test("a negotiated request never collapses")
    func negotiateNeverCollapses() {
        let outcome = WindowEngine.negotiate(target: CGRect(x: 0, y: 33, width: 100, height: 100),
                                             actual: CGRect(x: 0, y: 33, width: 500, height: 500),
                                             request: CGSize(width: 100, height: 100),
                                             screen: laptopVisible)
        #expect(outcome.request == CGSize(width: 1, height: 1))
    }

    @Test("a stored screen index is mapped onto the connected screens", arguments: [
        (screen: 0, count: 1, expected: 0),
        (screen: 1, count: 1, expected: 0),
        (screen: 1, count: 2, expected: 1),
        (screen: 5, count: 2, expected: 1),
        (screen: -3, count: 2, expected: 0),
        (screen: 0, count: 0, expected: 0),
    ])
    func screenIndexMapping(_ input: (screen: Int, count: Int, expected: Int)) {
        let window = WindowSnapshot(appName: "A", bundleIdentifier: "b",
                                    rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), screen: input.screen)
        #expect(WindowEngine.screenIndex(for: window, screenCount: input.count) == input.expected)
    }
}
