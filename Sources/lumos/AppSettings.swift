#if canImport(AppKit)
import Foundation

/// The persisted on/off toggles surfaced in the menu. Each is stored in
/// `UserDefaults` under a stable key so a relaunch restores the user's choices.
/// Defaults are chosen so a first launch is fully "on" and calm (no quiet hours,
/// not master-off) — sensible defaults over options, per the product contract.
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let notchGlow = "lumos.toggle.notchGlow"
        static let ledColor = "lumos.toggle.ledColor"
        static let showPercent = "lumos.toggle.showPercent"
        static let quietHours = "lumos.toggle.quietHours"
        static let masterOff = "lumos.toggle.masterOff"
        static let thinBar = "lumos.toggle.thinBar"
        static let onboardingSeen = "lumos.onboardingSeen"
        static let muteContext = "lumos.toggle.muteContext"
        static let muteTiming = "lumos.toggle.muteTiming"
        static let muteTip = "lumos.toggle.muteTip"
        static let updatesCheck = "lumos.toggle.updatesCheck"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.notchGlow: true,
            Key.ledColor: true,
            Key.showPercent: false,
            Key.quietHours: false,
            Key.masterOff: false,
            Key.thinBar: false,
            Key.onboardingSeen: false,
            Key.muteContext: false,
            Key.muteTiming: false,
            Key.muteTip: false,
            Key.updatesCheck: false
        ])
    }

    var notchGlowEnabled: Bool {
        get { defaults.bool(forKey: Key.notchGlow) }
        set { defaults.set(newValue, forKey: Key.notchGlow) }
    }

    var ledColorEnabled: Bool {
        get { defaults.bool(forKey: Key.ledColor) }
        set { defaults.set(newValue, forKey: Key.ledColor) }
    }

    var showPercentEnabled: Bool {
        get { defaults.bool(forKey: Key.showPercent) }
        set { defaults.set(newValue, forKey: Key.showPercent) }
    }

    var quietHoursEnabled: Bool {
        get { defaults.bool(forKey: Key.quietHours) }
        set { defaults.set(newValue, forKey: Key.quietHours) }
    }

    var masterOff: Bool {
        get { defaults.bool(forKey: Key.masterOff) }
        set { defaults.set(newValue, forKey: Key.masterOff) }
    }

    /// Non-notch Macs only: show the optional thin top-center glow bar in
    /// addition to the LED. Off by default (LED-only is the calmest default).
    var thinBarEnabled: Bool {
        get { defaults.bool(forKey: Key.thinBar) }
        set { defaults.set(newValue, forKey: Key.thinBar) }
    }

    var onboardingSeen: Bool {
        get { defaults.bool(forKey: Key.onboardingSeen) }
        set { defaults.set(newValue, forKey: Key.onboardingSeen) }
    }

    /// Per-type "don't show this kind again" mutes, mirrored into the notification
    /// engine so the menu checkmarks stay the fast, synchronous source of truth.
    var muteContext: Bool {
        get { defaults.bool(forKey: Key.muteContext) }
        set { defaults.set(newValue, forKey: Key.muteContext) }
    }

    var muteTiming: Bool {
        get { defaults.bool(forKey: Key.muteTiming) }
        set { defaults.set(newValue, forKey: Key.muteTiming) }
    }

    var muteTip: Bool {
        get { defaults.bool(forKey: Key.muteTip) }
        set { defaults.set(newValue, forKey: Key.muteTip) }
    }

    /// Opt-in, OFF by default: the once-a-day GitHub version check (the single
    /// optional network call Lumos ever makes). Nothing reaches the network until
    /// the user turns this on.
    var updatesCheckEnabled: Bool {
        get { defaults.bool(forKey: Key.updatesCheck) }
        set { defaults.set(newValue, forKey: Key.updatesCheck) }
    }
}
#endif
