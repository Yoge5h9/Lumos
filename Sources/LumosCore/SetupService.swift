import Foundation

/// Implements `lumos setup` / `lumos setup --uninstall`: non-destructively
/// wraps the existing Claude Code `statusLine.command` so it keeps rendering
/// exactly as before, while also teeing its stdin into `lumos ingest`.
///
/// Every path this touches is derived from `LumosPaths`, which honors env
/// overrides — callers running against a sandbox never touch a real
/// `~/.claude`. Every operation records enough state (`setup-state.json`) to
/// make `--uninstall` a byte-for-byte restore, and backs up before mutating
/// anything so a failed backup aborts with nothing changed.
public enum SetupService {
    public enum SetupError: Error, CustomStringConvertible {
        case settingsMalformed(URL)
        case backupFailed(URL, underlying: Error)
        case writeFailed(underlying: Error)
        case noSetupStateFound
        case restoreFailed(underlying: Error)

        public var description: String {
            switch self {
            case .settingsMalformed(let url):
                return "settings file at \(url.path) is not valid JSON — refusing to touch it"
            case .backupFailed(let url, let underlying):
                return "could not create a safe backup at \(url.path), aborting without changes: \(underlying)"
            case .writeFailed(let underlying):
                return "failed to write setup files: \(underlying)"
            case .noSetupStateFound:
                return "no Lumos setup state found — nothing to uninstall"
            case .restoreFailed(let underlying):
                return "failed to restore the original settings file: \(underlying)"
            }
        }
    }

    struct SetupState: Codable {
        let hadSettingsFile: Bool
        let backupPath: String?
        let wrapperScriptPath: String
        let cacheFilePath: String
        let originalStatusLineCommand: String?
    }

    private static let wrapperMarker = "# lumos-status-line-wrapper"

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func wrapperInvocation(wrapperScript: URL) -> String {
        "sh '\(wrapperScript.path)'"
    }

    private static func wrapperScriptContents(originalCommand: String?, cacheDir: URL, lumosExecutablePath: String) -> String {
        let originalPipe: String
        if let command = originalCommand, !command.isEmpty {
            originalPipe = "printf '%s' \"$input\" | \(command)\n"
        } else {
            originalPipe = ""
        }
        return """
        #!/bin/sh
        \(wrapperMarker)
        # The original status-line command only ever gets to read stdin once,
        # so it must be captured up front and replayed to every consumer.
        input=$(cat)
        \(originalPipe)printf '%s' "$input" | LUMOS_CACHE_DIR="\(cacheDir.path)" "\(lumosExecutablePath)" ingest >/dev/null 2>&1
        exit 0

        """
    }

    private static func loadSettingsDict(from url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SetupError.settingsMalformed(url)
        }
        guard !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dict = object as? [String: Any] else {
            throw SetupError.settingsMalformed(url)
        }
        return dict
    }

    /// Wraps the status line and starts caching. Idempotent: running this
    /// again when Lumos is already wrapped is a no-op that changes nothing.
    @discardableResult
    public static func setup(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        lumosExecutablePath: String
    ) throws -> String {
        let settingsURL = LumosPaths.settingsFile(environment: environment)
        let wrapperURL = LumosPaths.wrapperScriptFile(environment: environment)
        let stateURL = LumosPaths.setupStateFile(environment: environment)
        let cacheDirURL = LumosPaths.cacheDir(environment: environment)
        let cacheFileURL = LumosPaths.cacheFile(environment: environment)

        let hadSettingsFile = FileManager.default.fileExists(atPath: settingsURL.path)
        let settingsDict = try loadSettingsDict(from: settingsURL)

        let existingCommand = (settingsDict["statusLine"] as? [String: Any])?["command"] as? String
        let targetInvocation = wrapperInvocation(wrapperScript: wrapperURL)

        if let existingCommand, existingCommand == targetInvocation {
            return "Lumos is already set up. Your glow updates as you use Claude Code in the terminal."
        }

        var backupPath: String?
        if hadSettingsFile {
            let backupURL = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.bak-lumos-\(timestampFormatter.string(from: Date()))")
            do {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                try FileManager.default.copyItem(at: settingsURL, to: backupURL)
            } catch {
                throw SetupError.backupFailed(backupURL, underlying: error)
            }
            backupPath = backupURL.path
        }

        do {
            let wrapperContents = wrapperScriptContents(
                originalCommand: existingCommand,
                cacheDir: cacheDirURL,
                lumosExecutablePath: lumosExecutablePath
            )
            try AtomicFile.write(Data(wrapperContents.utf8), to: wrapperURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)

            var newSettingsDict = settingsDict
            newSettingsDict["statusLine"] = ["type": "command", "command": targetInvocation]
            let newSettingsData = try JSONSerialization.data(
                withJSONObject: newSettingsDict,
                options: [.prettyPrinted, .sortedKeys]
            )
            try AtomicFile.write(newSettingsData, to: settingsURL)

            let state = SetupState(
                hadSettingsFile: hadSettingsFile,
                backupPath: backupPath,
                wrapperScriptPath: wrapperURL.path,
                cacheFilePath: cacheFileURL.path,
                originalStatusLineCommand: existingCommand
            )
            let stateData = try JSONEncoder().encode(state)
            try AtomicFile.write(stateData, to: stateURL)
        } catch let error as SetupError {
            throw error
        } catch {
            throw SetupError.writeFailed(underlying: error)
        }

        let backupNote = backupPath.map { " (backup: \($0))" } ?? " (no prior settings file existed)"
        return """
        Lumos set up. Status line wrapped at \(wrapperURL.path)\(backupNote).
        Your glow updates as you use Claude Code in the terminal.
        """
    }

    /// Restores the original settings file byte-for-byte from its backup (or
    /// removes settings.json entirely if none existed before setup), then
    /// removes the wrapper script and cache. Leaves the backup file itself in
    /// place as an audit trail.
    @discardableResult
    public static func uninstall(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let stateURL = LumosPaths.setupStateFile(environment: environment)
        guard let stateData = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SetupState.self, from: stateData) else {
            throw SetupError.noSetupStateFound
        }

        let settingsURL = LumosPaths.settingsFile(environment: environment)

        do {
            if state.hadSettingsFile, let backupPath = state.backupPath {
                let backupURL = URL(fileURLWithPath: backupPath)
                if FileManager.default.fileExists(atPath: settingsURL.path) {
                    try FileManager.default.removeItem(at: settingsURL)
                }
                try FileManager.default.copyItem(at: backupURL, to: settingsURL)
            } else if FileManager.default.fileExists(atPath: settingsURL.path) {
                try FileManager.default.removeItem(at: settingsURL)
            }
        } catch {
            throw SetupError.restoreFailed(underlying: error)
        }

        try? FileManager.default.removeItem(at: URL(fileURLWithPath: state.wrapperScriptPath))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: state.cacheFilePath))
        try? FileManager.default.removeItem(at: stateURL)

        return "Lumos uninstalled — original status line restored."
    }
}
