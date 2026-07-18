#if canImport(AppKit)
import AppKit
import LumosCore

/// Renders the shared risk state as a menu-bar color. The palette itself lives
/// once in `LumosCore.UsageState` (`.hex`); this only turns it into an `NSColor`.
extension UsageState {
    var color: NSColor { NSColor(hex: hex) ?? .systemGray }
}

/// Resolves the LED's usage state from a cache aggregate via the real risk model
/// (`LumosCore.ColorModel`): usage × time-left × burn-rate, escalation gated
/// ≥45%, with stale/missing data and fresh windows never reading as Alert.
enum LEDColorSource {
    static func state(for aggregate: CacheAggregate) -> UsageState {
        ColorModel.state(aggregate: aggregate)
    }
}

extension NSColor {
    /// Parses `#RRGGBB` / `RRGGBB`. Returns nil on anything malformed.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
