#if canImport(AppKit)
import AppKit

/// Shared chrome + motion for the pill family (Readout and the notification
/// pills). The look is ported from `design/showcase.html`/`notifications.html`:
/// a blurred, translucent, rounded rectangle with a hairline border, and the
/// **Bleed** — the pill grows out of the notch from a notch-width sliver to full
/// size with a slight overshoot, and retracts the same way.
enum PillChrome {
    static let cornerRadius: CGFloat = 16

    /// A blurred translucent backdrop matching the pills' `backdrop-filter`
    /// blur + `rgba(30,30,33,.82)` fill + hairline border.
    static func makeBackdrop() -> NSVisualEffectView {
        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.borderWidth = 1
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        backdrop.layer?.masksToBounds = true
        return backdrop
    }

    /// Anchor a pill's layer at its top-center so the Bleed scales out of the
    /// notch rather than from its own middle. Call after the frame is set.
    static func prepareBleedAnchor(_ view: NSView) {
        guard let layer = view.layer else { return }
        let frame = view.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        // Non-flipped superview: the top edge sits at maxY.
        layer.position = CGPoint(x: frame.midX, y: frame.maxY)
    }

    /// The collapsed "sliver" state the pill emerges from / retracts to.
    private static var sliverTransform: CATransform3D {
        CATransform3DMakeScale(0.42, 0.06, 1)
    }

    /// Animate the pill in (`visible == true`) or out. Out calls `completion`
    /// after the retract finishes so the caller can remove it.
    static func bleed(
        _ view: NSView,
        visible: Bool,
        duration: CFTimeInterval = 0.36,
        completion: (() -> Void)? = nil
    ) {
        guard let layer = view.layer else { completion?(); return }
        prepareBleedAnchor(view)

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.22, 1, 0.32, 1)
        )
        if let completion { CATransaction.setCompletionBlock(completion) }
        layer.transform = visible ? CATransform3DIdentity : sliverTransform
        layer.opacity = visible ? 1 : 0
        CATransaction.commit()
    }

    /// Put a freshly-added pill into the collapsed, invisible state before its
    /// first Bleed-in, without animating.
    static func collapse(_ view: NSView) {
        guard let layer = view.layer else { return }
        prepareBleedAnchor(view)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = sliverTransform
        layer.opacity = 0
        CATransaction.commit()
    }
}
#endif
