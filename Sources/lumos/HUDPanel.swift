#if canImport(AppKit)
import AppKit

/// The menu-bar LED's hover **HUD** — a small, calm numbers pill shown beneath
/// the dot on hover (`% used · resets · wk %`), mirroring the notch Readout.
/// Click still opens the menu; this is the "hover = glance" half of the locked
/// LED interaction model. Non-interactive and click-through.
final class HUDPanel {
    private let panel: NSPanel
    private let readout = ReadoutView()
    private let margin: CGFloat = 6

    private(set) var isVisible = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none

        let content = NSView()
        content.wantsLayer = true
        content.layer?.masksToBounds = false
        content.addSubview(readout)
        panel.contentView = content
    }

    /// Show the HUD horizontally centered under `anchor` (the LED's screen rect).
    func show(below anchor: CGRect, fields: ReadoutFormatting.Fields, accent: NSColor) {
        let size = readout.update(fields: fields, accent: accent)
        let panelSize = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
        readout.setFrameOrigin(NSPoint(x: margin, y: margin))

        let originX = anchor.midX - panelSize.width / 2
        let originY = anchor.minY - panelSize.height - 4
        panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height), display: true)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }
}
#endif
