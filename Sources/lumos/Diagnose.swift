#if canImport(AppKit)
import AppKit
import CoreGraphics

/// `lumos diagnose` — prints the notch/screen facts Lumos resolves, then exits.
/// Never shows UI and never enters the run loop; it brings `NSApplication` up
/// just far enough (`.accessory` + `finishLaunching`) to read `NSScreen`.
///
/// Reuses the real detection code (`NotchGeometry`, `NotchProfileTable`) so the
/// output reflects exactly what the running app would compute. On a non-notch
/// Mac it correctly reports "notch: no" — that is expected, not an error.
enum Diagnose {
    /// The overlay window level `NotchWindowController` uses (one above the menu
    /// bar). Kept in sync with `NotchWindow.buildWindow()`.
    private static let overlayWindowLevel = NSWindow.Level.mainMenu.rawValue + 1

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        var lines: [String] = []
        func line(_ text: String = "") { lines.append(text) }

        let modelID = SystemModel.modelIdentifier()
        let match = NotchProfileTable.matchCurrent()

        line("Lumos diagnose")
        line()
        line("Machine")
        line("  model id:        \(modelID.isEmpty ? "unknown" : modelID)")
        if let label = SystemModel.humanLabel(for: modelID) {
            line("  model:           \(label)")
        }

        line()
        let screens = NSScreen.screens
        line("Screens (\(screens.count))")
        if screens.isEmpty {
            line("  none readable headlessly (no window server session?)")
        }
        for (index, screen) in screens.enumerated() {
            let points = screen.frame
            let backing = screen.convertRectToBacking(points)
            let builtin = isBuiltIn(screen) ? "built-in" : "external"
            line("  [\(index)] \(builtin)")
            line("      points:        \(fmt(points.width)) x \(fmt(points.height))")
            line("      backing (px):  \(fmt(backing.width)) x \(fmt(backing.height))  @\(fmt(screen.backingScaleFactor))x")
            line("      safeArea.top:  \(fmt(screen.safeAreaInsets.top))")
        }

        line()
        line("Notch")
        let geometry = NotchGeometry.detect()
        if geometry.hasNotch {
            line("  detected:        yes")
            line("  safeArea.top:    \(fmt(geometry.screen.safeAreaInsets.top))")
            line("  width x height:  \(fmt(geometry.notchFrame.width)) x \(fmt(geometry.notchFrame.height))")
        } else {
            line("  detected:        no (no screen reports a top safe-area inset)")
        }

        line()
        line("Profile")
        line("  matched family:  \(match.family)")
        line("  corner-radius:   \(fmt(match.profile.cornerRadius))")
        line("  default fallback:\(match.isDefaultFallback ? " yes" : " no")")
        if let w = match.profile.widthBounds {
            line("  width bounds:    \(fmt(w.lowerBound))...\(fmt(w.upperBound))")
        }
        if let h = match.profile.heightBounds {
            line("  height bounds:   \(fmt(h.lowerBound))...\(fmt(h.upperBound))")
        }

        line()
        line("Overlay")
        line("  window level:    \(overlayWindowLevel) (mainMenu + 1)")
        if geometry.hasNotch {
            line("  surface:         Halo + Bloom around the notch")
        } else {
            line("  surface:         non-notch fallback — menu-bar LED only (optional thin bar)")
        }

        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        exit(0)
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%g", Double(value))
    }
}
#endif
