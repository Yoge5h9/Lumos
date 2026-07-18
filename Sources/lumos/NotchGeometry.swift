#if canImport(AppKit)
import AppKit

/// The resolved position of the notch (or a fallback strip) on a physical
/// display, in global screen coordinates (bottom-left origin), plus the corner
/// radius its bottom edges should trace.
struct NotchGeometry: Equatable {
    let screen: NSScreen
    /// The notch cut-out itself in global coordinates: top edge at the screen's
    /// physical top, height equal to the menu-bar safe-area inset.
    let notchFrame: CGRect
    let cornerRadius: CGFloat
    let hasNotch: Bool

    /// Finds a display whose top safe-area inset is non-zero (a notched Mac) and
    /// measures the cut-out from the two auxiliary menu-bar areas flanking it.
    /// Width is the gap between those areas; the notch is centered on the screen.
    /// Falls back to a thin, centered top strip when no notch exists.
    static func detect() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            let width = max(right.minX - left.maxX, 120)
            let centerX = screen.frame.midX
            let frame = CGRect(
                x: centerX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
            // Corner-radius has no runtime API; source it from the per-model table
            // (safe default for unknown/future Macs) rather than a bare constant.
            let cornerRadius = NotchProfileTable.matchCurrent().profile.cornerRadius
            return NotchGeometry(screen: screen, notchFrame: frame, cornerRadius: cornerRadius, hasNotch: true)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 200
        let height: CGFloat = 32
        let frame = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        return NotchGeometry(screen: screen, notchFrame: frame, cornerRadius: 10, hasNotch: false)
    }

    /// The global frame for the borderless overlay window: pinned to the physical
    /// top edge of the notched screen, centered on the notch, wide enough for the
    /// widest pill and tall enough for the notch plus a downward "Bleed" drop.
    func overlayWindowFrame(dropHeight: CGFloat) -> CGRect {
        let width = max(notchFrame.width + 160, 400)
        let notchHeight = hasNotch ? notchFrame.height : 6
        let height = notchHeight + dropHeight
        let centerX = notchFrame.midX
        return CGRect(
            x: centerX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// The notch height to render inside the overlay (the physical cut-out on a
    /// notched Mac; a thin strip otherwise so the Bleed has a top anchor).
    var renderNotchHeight: CGFloat { hasNotch ? notchFrame.height : 6 }
}
#endif
