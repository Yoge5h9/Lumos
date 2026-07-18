#if canImport(AppKit)
import AppKit

/// Draws the menu-bar LED dot programmatically — a filled disc with a soft bloom
/// halo, matching the `.led` treatment in `design/showcase.html` (an 11px dot
/// with a `0 0 7px` colored glow). Rendered at 2x into an off-screen bitmap so it
/// stays crisp on Retina menu bars.
enum StatusItemLED {
    /// `opacity` dims the whole dot (bloom + core) for a Stale reading — the
    /// menu-bar counterpart to the Halo's dimmed glow. Left at `1` when live.
    static func image(color: NSColor, monochrome: Bool, opacity: CGFloat = 1) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let alpha = monochrome ? 1 : max(0, min(1, opacity))
        let fill = monochrome ? NSColor.black : color
        let center = NSRect(x: 4.5, y: 4.5, width: 7, height: 7)

        if !monochrome {
            fill.withAlphaComponent(0.30 * alpha).setFill()
            NSBezierPath(ovalIn: center.insetBy(dx: -3, dy: -3)).fill()
            fill.withAlphaComponent(0.45 * alpha).setFill()
            NSBezierPath(ovalIn: center.insetBy(dx: -1.5, dy: -1.5)).fill()
        }

        fill.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: center).fill()

        image.unlockFocus()
        // A monochrome dot becomes a template so AppKit tints it to match the
        // menu bar (light/dark); a colored dot must render its own color.
        image.isTemplate = monochrome
        return image
    }
}
#endif
