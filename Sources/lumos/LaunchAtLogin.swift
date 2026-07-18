#if canImport(AppKit)
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the in-app launch-at-login
/// toggle (macOS 13+). Reads live status rather than mirroring it into
/// `UserDefaults`, so the checkmark always reflects the real login-item state.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Register/unregister the main app as a login item. Returns whether the
    /// call succeeded so the caller can leave the toggle unchanged on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
#endif
