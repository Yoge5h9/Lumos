import Foundation

/// Resolves every filesystem location Lumos touches from a single, overridable base.
///
/// Production defaults mirror the real Claude Code layout (`~/.claude`, with Lumos'
/// own state under `~/.claude/lumos/`). Every path also honors an environment override
/// so setup/ingest logic can be exercised against a disposable sandbox instead of a
/// developer's live `~/.claude` directory.
public enum LumosPaths {
    public static let claudeHomeDirEnvKey = "LUMOS_CLAUDE_DIR"
    public static let cacheDirEnvKey = "LUMOS_CACHE_DIR"

    /// The Claude Code home directory (`~/.claude` in production).
    public static func claudeHomeDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[claudeHomeDirEnvKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    /// The directory Lumos owns for its own state (cache, wrapper script, setup marker).
    /// Defaults to `<claudeHomeDir>/lumos`, but can be pointed anywhere independently —
    /// this is what `lumos ingest` honors so it never needs the rest of the settings layout.
    public static func cacheDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[cacheDirEnvKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return claudeHomeDir(environment: environment).appendingPathComponent("lumos", isDirectory: true)
    }

    public static func cacheFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        cacheDir(environment: environment).appendingPathComponent("cache.json", isDirectory: false)
    }

    public static func settingsFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        claudeHomeDir(environment: environment).appendingPathComponent("settings.json", isDirectory: false)
    }

    public static func historyFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        claudeHomeDir(environment: environment).appendingPathComponent("history.jsonl", isDirectory: false)
    }

    public static func wrapperScriptFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        cacheDir(environment: environment).appendingPathComponent("statusline-wrapper.sh", isDirectory: false)
    }

    public static func setupStateFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        cacheDir(environment: environment).appendingPathComponent("setup-state.json", isDirectory: false)
    }
}
