import AppKit

struct LiveResizeRubberBanding {
    static let resistance: CGFloat = 0.05
    static let releaseDuration: TimeInterval = 0.24

    struct ResizeEdges: OptionSet {
        let rawValue: Int

        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let bottom = ResizeEdges(rawValue: 1 << 2)
        static let top = ResizeEdges(rawValue: 1 << 3)
    }

    struct Session {
        let initialFrame: NSRect
        let initialMouseLocation: NSPoint
        let edges: ResizeEdges
        let minSize: NSSize
    }

    struct Result {
        let displayFrame: NSRect
        let settleFrame: NSRect
        let isRubberBanding: Bool
    }

    static func dragEdges(
        for mouseLocation: NSPoint,
        in frame: NSRect,
        threshold: CGFloat = 24
    ) -> ResizeEdges {
        let leftDistance = abs(mouseLocation.x - frame.minX)
        let rightDistance = abs(mouseLocation.x - frame.maxX)
        let bottomDistance = abs(mouseLocation.y - frame.minY)
        let topDistance = abs(mouseLocation.y - frame.maxY)

        var edges: ResizeEdges = []
        if min(leftDistance, rightDistance) <= threshold {
            edges.insert(leftDistance <= rightDistance ? .left : .right)
        }
        if min(bottomDistance, topDistance) <= threshold {
            edges.insert(bottomDistance <= topDistance ? .bottom : .top)
        }

        if edges.isEmpty {
            if min(leftDistance, rightDistance) <= min(bottomDistance, topDistance) {
                edges.insert(leftDistance <= rightDistance ? .left : .right)
            } else {
                edges.insert(bottomDistance <= topDistance ? .bottom : .top)
            }
        }

        return edges
    }

    static func result(
        for session: Session,
        currentMouseLocation: NSPoint
    ) -> Result {
        var settleFrame = session.initialFrame
        var displayFrame = session.initialFrame
        var isRubberBanding = false

        if session.edges.contains(.left) {
            let delta = currentMouseLocation.x - session.initialMouseLocation.x
            let proposedWidth = session.initialFrame.width - delta
            let settledWidth = max(session.minSize.width, proposedWidth)
            let overshoot = max(0, session.minSize.width - proposedWidth)

            settleFrame.size.width = settledWidth
            settleFrame.origin.x = session.initialFrame.maxX - settledWidth

            displayFrame.size.width = settledWidth
            displayFrame.origin.x = settleFrame.origin.x + rubberBandDistance(
                overshoot: overshoot,
                dimension: session.minSize.width
            )
            isRubberBanding = isRubberBanding || overshoot > 0
        } else if session.edges.contains(.right) {
            let delta = currentMouseLocation.x - session.initialMouseLocation.x
            let proposedWidth = session.initialFrame.width + delta
            let settledWidth = max(session.minSize.width, proposedWidth)
            let overshoot = max(0, session.minSize.width - proposedWidth)

            settleFrame.size.width = settledWidth
            settleFrame.origin.x = session.initialFrame.origin.x

            displayFrame.size.width = settledWidth
            displayFrame.origin.x = settleFrame.origin.x - rubberBandDistance(
                overshoot: overshoot,
                dimension: session.minSize.width
            )
            isRubberBanding = isRubberBanding || overshoot > 0
        }

        if session.edges.contains(.bottom) {
            let delta = currentMouseLocation.y - session.initialMouseLocation.y
            let proposedHeight = session.initialFrame.height - delta
            let settledHeight = max(session.minSize.height, proposedHeight)
            let overshoot = max(0, session.minSize.height - proposedHeight)

            settleFrame.size.height = settledHeight
            settleFrame.origin.y = session.initialFrame.maxY - settledHeight

            displayFrame.size.height = settledHeight
            displayFrame.origin.y = settleFrame.origin.y + rubberBandDistance(
                overshoot: overshoot,
                dimension: session.minSize.height
            )
            isRubberBanding = isRubberBanding || overshoot > 0
        } else if session.edges.contains(.top) {
            let delta = currentMouseLocation.y - session.initialMouseLocation.y
            let proposedHeight = session.initialFrame.height + delta
            let settledHeight = max(session.minSize.height, proposedHeight)
            let overshoot = max(0, session.minSize.height - proposedHeight)

            settleFrame.size.height = settledHeight
            settleFrame.origin.y = session.initialFrame.origin.y

            displayFrame.size.height = settledHeight
            displayFrame.origin.y = settleFrame.origin.y - rubberBandDistance(
                overshoot: overshoot,
                dimension: session.minSize.height
            )
            isRubberBanding = isRubberBanding || overshoot > 0
        }

        return Result(
            displayFrame: displayFrame,
            settleFrame: settleFrame,
            isRubberBanding: isRubberBanding
        )
    }

    static func rubberBandDistance(
        overshoot: CGFloat,
        dimension: CGFloat,
        resistance: CGFloat = resistance
    ) -> CGFloat {
        guard overshoot > 0, dimension > 0 else { return 0 }
        // Use an unbounded inverse-hyperbolic-sine decay so the panel keeps
        // following the pointer well past the minimum threshold, but with
        // diminishing returns rather than a hard-feeling cap.
        return (dimension * resistance) * asinh(overshoot / dimension)
    }
}
