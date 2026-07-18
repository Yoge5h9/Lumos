#if canImport(AppKit)
import AppKit

/// Draws the **Halo** (the colored ring hugging the notch's sides + bottom) and
/// its **Bloom** (the soft outer glow), ported from the `.halo` treatment in
/// `design/showcase.html` — a thin ring with `border-top:none`, rounded bottom
/// corners, and a colored `drop-shadow`. On a non-notch Mac the same view renders
/// the optional thin top-center **glow bar** finalist from `design/non-notch.html`.
///
/// Brightness is driven by a single `glowLevel` (`0...1`, the interactions.html
/// `--lum`): it scales the ring's opacity and the Bloom's radius/strength so the
/// glow can rest dim and bloom bright. `GlowController` animates that value.
final class HaloView: NSView {
    enum Mode: Equatable {
        case notch(width: CGFloat, height: CGFloat, cornerRadius: CGFloat)
        case thinBar(width: CGFloat)
    }

    /// Ring thickness in points (showcase `--thick`, 2.5).
    private let thickness: CGFloat = 2.5
    /// Base Bloom radius the glow level scales (interactions `--glow-base`, tuned up
    /// slightly for physical-pixel notch dimensions vs the CSS mock).
    private let bloomBase: CGFloat = 9

    private var mode: Mode = .notch(width: 200, height: 38, cornerRadius: 14)
    private var color: NSColor = .systemGray
    private(set) var glowLevel: CGFloat = 0.30

    private let ringLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineJoin = .round
        ringLayer.lineCap = .round
        ringLayer.shadowOffset = .zero
        ringLayer.masksToBounds = false
        layer?.addSublayer(ringLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    func configure(mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        needsLayout = true
    }

    override func layout() {
        super.layout()
        ringLayer.frame = bounds
        rebuildPath()
        applyGlow(animated: false)
    }

    // MARK: - Path

    private func rebuildPath() {
        let path = CGMutablePath()
        let t = thickness
        switch mode {
        case let .notch(w, h, cornerRadius):
            let notchMinX = (bounds.width - w) / 2
            let xL = notchMinX - t / 2
            let xR = notchMinX + w + t / 2
            let yTop = bounds.maxY
            let yBot = bounds.maxY - h - t / 2
            let rr = cornerRadius
            path.move(to: CGPoint(x: xL, y: yTop))
            path.addLine(to: CGPoint(x: xL, y: yBot + rr))
            path.addQuadCurve(to: CGPoint(x: xL + rr, y: yBot), control: CGPoint(x: xL, y: yBot))
            path.addLine(to: CGPoint(x: xR - rr, y: yBot))
            path.addQuadCurve(to: CGPoint(x: xR, y: yBot + rr), control: CGPoint(x: xR, y: yBot))
            path.addLine(to: CGPoint(x: xR, y: yTop))
            ringLayer.lineWidth = t

        case let .thinBar(w):
            // A slim rounded glow line centered at the very top — a hint, not a shape.
            let barHeight: CGFloat = 4
            let x0 = (bounds.width - w) / 2
            let yMid = bounds.maxY - barHeight / 2
            path.move(to: CGPoint(x: x0, y: yMid))
            path.addLine(to: CGPoint(x: x0 + w, y: yMid))
            ringLayer.lineWidth = barHeight
        }
        ringLayer.path = path
    }

    // MARK: - Color & glow

    func setColor(_ color: NSColor, animated: Bool, duration: CFTimeInterval = 0.4) {
        self.color = color
        applyGlow(animated: animated, duration: duration)
    }

    /// Sets the current brightness (`0...1`) and repaints. `duration` drives the
    /// Core Animation interpolation so the caller controls wake/fade timing.
    func setGlowLevel(_ level: CGFloat, duration: CFTimeInterval) {
        glowLevel = max(0, min(1, level))
        applyGlow(animated: true, duration: duration)
    }

    private func applyGlow(animated: Bool, duration: CFTimeInterval = 0.4) {
        let lum = glowLevel
        let ringOpacity = Float(0.34 + 0.66 * lum)
        let bloomRadius = bloomBase * (0.9 + 1.6 * lum)
        let bloomOpacity = Float(0.42 + 0.5 * lum)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(controlPoints: 0.33, 0.9, 0.36, 1)
            )
        }
        ringLayer.strokeColor = color.cgColor
        ringLayer.shadowColor = color.cgColor
        ringLayer.opacity = ringOpacity
        ringLayer.shadowRadius = bloomRadius
        ringLayer.shadowOpacity = bloomOpacity
        CATransaction.commit()
    }
}
#endif
