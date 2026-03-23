import AppKit
import XCTest
@testable import FloatyDoLib

final class FloatingPanelRubberBandingTests: XCTestCase {
    func testDragEdgesDetectsBottomRightCorner() {
        let frame = NSRect(x: 100, y: 100, width: 360, height: 280)
        let edges = LiveResizeRubberBanding.dragEdges(
            for: NSPoint(x: frame.maxX - 2, y: frame.minY + 3),
            in: frame
        )

        XCTAssertEqual(edges, [.right, .bottom])
    }

    func testResultWithoutOvershootMatchesStandardRightEdgeResize() {
        let session = LiveResizeRubberBanding.Session(
            initialFrame: NSRect(x: 100, y: 100, width: 360, height: 280),
            initialMouseLocation: NSPoint(x: 460, y: 240),
            edges: [.right],
            minSize: NSSize(width: 320, height: 200)
        )
        let result = LiveResizeRubberBanding.result(
            for: session,
            currentMouseLocation: NSPoint(x: 430, y: 240)
        )

        XCTAssertFalse(result.isRubberBanding)
        XCTAssertEqual(result.displayFrame.width, 330, accuracy: 0.5)
        XCTAssertEqual(result.displayFrame.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(result.displayFrame, result.settleFrame)
    }

    func testLeftEdgeOvershootShiftsWindowRightWithMinWidthPinned() {
        let session = LiveResizeRubberBanding.Session(
            initialFrame: NSRect(x: 100, y: 100, width: 320, height: 240),
            initialMouseLocation: NSPoint(x: 100, y: 220),
            edges: [.left],
            minSize: NSSize(width: 320, height: 200)
        )
        let result = LiveResizeRubberBanding.result(
            for: session,
            currentMouseLocation: NSPoint(x: 160, y: 220)
        )

        XCTAssertTrue(result.isRubberBanding)
        XCTAssertEqual(result.displayFrame.width, 320, accuracy: 0.5)
        XCTAssertEqual(result.settleFrame.origin.x, 100, accuracy: 0.5)
        XCTAssertGreaterThan(result.displayFrame.origin.x, result.settleFrame.origin.x)
    }

    func testRightEdgeOvershootShiftsWindowLeftWithMinWidthPinned() {
        let session = LiveResizeRubberBanding.Session(
            initialFrame: NSRect(x: 100, y: 100, width: 320, height: 240),
            initialMouseLocation: NSPoint(x: 420, y: 220),
            edges: [.right],
            minSize: NSSize(width: 320, height: 200)
        )
        let result = LiveResizeRubberBanding.result(
            for: session,
            currentMouseLocation: NSPoint(x: 360, y: 220)
        )

        XCTAssertTrue(result.isRubberBanding)
        XCTAssertEqual(result.displayFrame.width, 320, accuracy: 0.5)
        XCTAssertEqual(result.settleFrame.origin.x, 100, accuracy: 0.5)
        XCTAssertLessThan(result.displayFrame.origin.x, result.settleFrame.origin.x)
    }

    func testBottomRightCornerOvershootBandsOnBothAxes() {
        let session = LiveResizeRubberBanding.Session(
            initialFrame: NSRect(x: 100, y: 100, width: 320, height: 220),
            initialMouseLocation: NSPoint(x: 420, y: 100),
            edges: [.right, .bottom],
            minSize: NSSize(width: 320, height: 220)
        )
        let result = LiveResizeRubberBanding.result(
            for: session,
            currentMouseLocation: NSPoint(x: 360, y: 140)
        )

        XCTAssertTrue(result.isRubberBanding)
        XCTAssertEqual(result.displayFrame.width, 320, accuracy: 0.5)
        XCTAssertEqual(result.displayFrame.height, 220, accuracy: 0.5)
        XCTAssertLessThan(result.displayFrame.origin.x, result.settleFrame.origin.x)
        XCTAssertGreaterThan(result.displayFrame.origin.y, result.settleFrame.origin.y)
    }

    func testRubberBandDistanceDampsOvershoot() {
        let overshoot: CGFloat = 80
        let banded = LiveResizeRubberBanding.rubberBandDistance(overshoot: overshoot, dimension: 320)

        XCTAssertGreaterThan(banded, 0)
        XCTAssertLessThan(banded, overshoot)
    }

    func testRubberBandDistanceKeepsGrowingWithoutHardCap() {
        let medium = LiveResizeRubberBanding.rubberBandDistance(overshoot: 400, dimension: 320)
        let large = LiveResizeRubberBanding.rubberBandDistance(overshoot: 4_000, dimension: 320)
        let veryLarge = LiveResizeRubberBanding.rubberBandDistance(overshoot: 40_000, dimension: 320)

        XCTAssertGreaterThan(large, medium)
        XCTAssertGreaterThan(veryLarge, large)
    }

    func testRightEdgeOvershootFromExactMinimumStillRubberBands() {
        let minSize = NSSize(width: 320, height: 220)
        let session = LiveResizeRubberBanding.Session(
            initialFrame: NSRect(x: 100, y: 100, width: minSize.width, height: minSize.height),
            initialMouseLocation: NSPoint(x: 420, y: 210),
            edges: [.right],
            minSize: minSize
        )
        let result = LiveResizeRubberBanding.result(
            for: session,
            currentMouseLocation: NSPoint(x: 340, y: 210)
        )

        XCTAssertTrue(result.isRubberBanding)
        XCTAssertEqual(result.displayFrame.size, minSize)
        XCTAssertLessThan(result.displayFrame.origin.x, result.settleFrame.origin.x)
    }
}
