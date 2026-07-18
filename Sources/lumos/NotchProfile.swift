#if canImport(AppKit)
import Foundation

/// Reads immutable hardware facts about the running Mac.
enum SystemModel {
    /// The machine's model identifier (e.g. `Mac14,7`, `MacBookPro18,3`).
    /// Empty string if it can't be read.
    static func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    /// A rough human label derived from the model-id family, best-effort only.
    static func humanLabel(for modelIdentifier: String) -> String? {
        if modelIdentifier.hasPrefix("Mac16") { return "Apple silicon (M4 generation)" }
        if modelIdentifier.hasPrefix("Mac15") { return "Apple silicon (M3 generation)" }
        if modelIdentifier.hasPrefix("Mac14") { return "Apple silicon (M2 generation)" }
        if modelIdentifier.hasPrefix("Mac13") { return "Apple silicon (Mac Studio / M-series)" }
        if modelIdentifier.hasPrefix("MacBookPro18") { return "Apple silicon (M1 Pro/Max MacBook Pro)" }
        if modelIdentifier.hasPrefix("MacBook") || modelIdentifier.hasPrefix("iMac") || modelIdentifier.hasPrefix("Macmini") {
            return "Intel Mac"
        }
        return nil
    }
}

/// Per-hardware-family notch rendering hints that AppKit does NOT expose at
/// runtime. Notch *presence*, *width*, and *height* are all measured live from
/// `safeAreaInsets` / the auxiliary menu-bar areas (see `NotchGeometry`); the one
/// missing piece is the **corner-radius** of the cut-out's bottom fillets, which
/// has no public API. This table supplies it per model-id family.
///
/// Values are approximate and expected to be refined from real `lumos diagnose`
/// output on physical hardware. The optional width/height bounds are loose sanity
/// ranges (points) for the family, not hard gates.
struct NotchProfile: Equatable {
    let cornerRadius: CGFloat
    let widthBounds: ClosedRange<CGFloat>?
    let heightBounds: ClosedRange<CGFloat>?
}

/// The outcome of matching the running machine against the profile table.
struct NotchProfileMatch: Equatable {
    let profile: NotchProfile
    /// The family prefix that matched (e.g. `Mac15`), or `"default"` when the
    /// safe fallback was used.
    let family: String
    /// True when no family matched and the safe default was substituted — the
    /// expected path for any unknown or future Mac.
    let isDefaultFallback: Bool
}

enum NotchProfileTable {
    /// Safe default for unknown / future models so new hardware still renders a
    /// reasonable Halo rather than nothing.
    static let fallback = NotchProfile(cornerRadius: 14, widthBounds: nil, heightBounds: nil)

    /// Ordered by prefix; first match wins. Radii are close across the current
    /// notched line-up; the table exists so a family that differs can be corrected
    /// without touching detection logic.
    private static let families: [(prefix: String, profile: NotchProfile)] = [
        ("Mac16", NotchProfile(cornerRadius: 14, widthBounds: 170...260, heightBounds: 28...44)),
        ("Mac15", NotchProfile(cornerRadius: 14, widthBounds: 170...260, heightBounds: 28...44)),
        ("Mac14", NotchProfile(cornerRadius: 14, widthBounds: 170...260, heightBounds: 28...44)),
        ("MacBookPro18", NotchProfile(cornerRadius: 13, widthBounds: 170...260, heightBounds: 28...44)),
    ]

    static func match(forModelIdentifier modelIdentifier: String) -> NotchProfileMatch {
        for entry in families where modelIdentifier.hasPrefix(entry.prefix) {
            return NotchProfileMatch(profile: entry.profile, family: entry.prefix, isDefaultFallback: false)
        }
        return NotchProfileMatch(profile: fallback, family: "default", isDefaultFallback: true)
    }

    /// Convenience: match against the currently-running machine.
    static func matchCurrent() -> NotchProfileMatch {
        match(forModelIdentifier: SystemModel.modelIdentifier())
    }
}
#endif
