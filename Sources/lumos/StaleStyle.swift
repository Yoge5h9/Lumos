#if canImport(AppKit)
import AppKit
import LumosCore

/// The single source of truth for how a Stale state reads, ported from the
/// signed-off `design/stale-states.html`. Stale keeps the state hue but greys it
/// toward a warm neutral and dims it — "muted mustard", unmistakably still the
/// Watch/Alert/Calm colour, never a different colour and never neutral gray.
///
/// The freshness threshold itself lives once in
/// `LumosCore.CacheAggregator.defaultStalenessThreshold`; this holds the two
/// visual magic numbers that pair with it.
enum StaleStyle {
    /// Fraction mixed from the state hue toward `warmNeutral`. At `0.60` the
    /// amber `#FFD60A` resolves to ≈`rgb(188, 167, 77)` — clearly yellow, not gray.
    static let desaturation: CGFloat = 0.60
    /// How far brightness/glow drops for Stale (HTML `dimAmt`); the resting glow
    /// level becomes `1 - dim`.
    static let dim: CGFloat = 0.45
    /// The warm neutral the hue is mixed toward (HTML `--mute: #8f877a`).
    static let warmNeutral = NSColor(srgbRed: 143.0/255, green: 135.0/255, blue: 122.0/255, alpha: 1)
    /// Live → Stale eases in over this long, then holds still (no breathing).
    static let fadeDuration: CFTimeInterval = 2.2

    /// The static glow level a Stale surface rests at (dimmed, never blooming).
    static var glowLevel: CGFloat { 1 - dim }
}

extension NSColor {
    /// The Stale rendering of a state colour: desaturated `desaturation` toward
    /// the warm neutral. The dim axis is applied separately by the render layer
    /// (glow level / dot opacity), matching how the HTML separates `--desat`
    /// from `--lum`.
    func staled() -> NSColor {
        let base = usingColorSpace(.sRGB) ?? self
        let mix = StaleStyle.desaturation
        let neutral = StaleStyle.warmNeutral
        return NSColor(
            srgbRed: base.redComponent * (1 - mix) + neutral.redComponent * mix,
            green: base.greenComponent * (1 - mix) + neutral.greenComponent * mix,
            blue: base.blueComponent * (1 - mix) + neutral.blueComponent * mix,
            alpha: base.alphaComponent
        )
    }
}
#endif
