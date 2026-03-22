import AppKit
import QuartzCore

class PressScaleButton: NSButton {
    var pressedScale: CGFloat = 0.97
    var suppressSystemHighlight = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func highlight(_ flag: Bool) {
        guard !suppressSystemHighlight else { return }
        super.highlight(flag)
    }

    override func mouseDown(with event: NSEvent) {
        setPressedAppearance(true, duration: 0.08)
        super.mouseDown(with: event)
        setPressedAppearance(false, duration: 0.12)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCellHighlightBehavior()
    }

    private func setPressedAppearance(_ pressed: Bool, duration: CFTimeInterval) {
        wantsLayer = true
        guard let layer else { return }

        let scale = pressed ? pressedScale : 1
        let targetTransform = centeredPressTransform(scale: scale)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.presentation()?.transform ?? layer.transform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.removeAnimation(forKey: "pressScale")
        layer.add(animation, forKey: "pressScale")
        layer.transform = targetTransform
    }

    private func centeredPressTransform(scale: CGFloat) -> CATransform3D {
        let centerX = bounds.midX
        let centerY = bounds.midY

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, centerX, centerY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -centerX, -centerY, 0)
        return transform
    }

    private func updateCellHighlightBehavior() {
        guard suppressSystemHighlight, let cell = cell as? NSButtonCell else { return }
        cell.highlightsBy = []
        cell.showsStateBy = []
    }
}
