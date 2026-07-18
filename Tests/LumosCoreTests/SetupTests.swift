import Testing
import Foundation
@testable import LumosCore

@Suite final class SetupTests {
    private let sandbox: URL
    private let environment: [String: String]
    private let fakeLumosBinaryPath = "/opt/homebrew/bin/lumos"

    init() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        environment = ["LUMOS_CLAUDE_DIR": sandbox.path]
    }

    deinit {
        // Undo any permission lockdown a test applied, or cleanup would silently fail.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.path)
        try? FileManager.default.removeItem(at: sandbox)
    }

    private var settingsURL: URL { LumosPaths.settingsFile(environment: environment) }

    @discardableResult
    private func writeFakeSettings(statusLineCommand: String?) throws -> Data {
        var dict: [String: Any] = [
            "model": "opus[1m]",
            "permissions": ["allow": ["WebSearch"]]
        ]
        if let statusLineCommand {
            dict["statusLine"] = ["type": "command", "command": statusLineCommand]
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
        return data
    }

    private func backupFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("settings.json.bak-lumos-") } ?? []
    }

    private func commandFromSettings() throws -> String {
        let dict = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        let statusLine = dict?["statusLine"] as? [String: Any]
        return try #require(statusLine?["command"] as? String)
    }

    // MARK: - Wrap + backup

    @Test func setupWrapsExistingStatusLineAndBacksUp() throws {
        let originalData = try writeFakeSettings(statusLineCommand: "sh /original/statusline.sh")

        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)

        let backups = backupFiles()
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == originalData, "backup must be byte-for-byte")

        let newSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        let statusLine = newSettings?["statusLine"] as? [String: Any]
        let newCommand = try #require(statusLine?["command"] as? String)

        let wrapperURL = LumosPaths.wrapperScriptFile(environment: environment)
        #expect(newCommand == "sh '\(wrapperURL.path)'")
        #expect(newSettings?["model"] as? String == "opus[1m]", "unrelated keys must survive untouched")

        let wrapperContents = try String(contentsOf: wrapperURL, encoding: .utf8)
        #expect(wrapperContents.contains("sh /original/statusline.sh"))
        #expect(wrapperContents.contains(fakeLumosBinaryPath))
        #expect(wrapperContents.contains("ingest"))
        #expect(wrapperContents.contains(LumosPaths.cacheDir(environment: environment).path))

        let attrs = try FileManager.default.attributesOfItem(atPath: wrapperURL.path)
        let permissions = attrs[.posixPermissions] as? Int
        #expect(((permissions ?? 0) & 0o100) == 0o100, "wrapper script must be executable")
    }

    @Test func setupWithNoExistingSettingsFileWrapsWithEmptyOriginal() throws {
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))

        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)

        #expect(backupFiles().isEmpty, "nothing existed to back up")
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))

        let wrapperURL = LumosPaths.wrapperScriptFile(environment: environment)
        let contents = try String(contentsOf: wrapperURL, encoding: .utf8)
        #expect(!contents.contains("/original/"))
    }

    // MARK: - Idempotency

    @Test func runningSetupTwiceDoesNotDoubleWrap() throws {
        try writeFakeSettings(statusLineCommand: "sh /original/statusline.sh")

        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)
        let firstCommand = try commandFromSettings()

        let message = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)

        #expect(backupFiles().count == 1, "second run must not create another backup")
        #expect(try commandFromSettings() == firstCommand, "second run must not re-wrap the wrapper")
        #expect(message.lowercased().contains("already set up"))
    }

    // MARK: - Uninstall round-trip

    @Test func uninstallRestoresOriginalByteForByte() throws {
        let originalData = try writeFakeSettings(statusLineCommand: "sh /original/statusline.sh")

        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)
        #expect(try Data(contentsOf: settingsURL) != originalData, "sanity: setup must have changed the file")

        _ = try SetupService.uninstall(environment: environment)

        #expect(try Data(contentsOf: settingsURL) == originalData, "uninstall must restore the exact original bytes")
        #expect(!FileManager.default.fileExists(atPath: LumosPaths.wrapperScriptFile(environment: environment).path))
        #expect(!FileManager.default.fileExists(atPath: LumosPaths.setupStateFile(environment: environment).path))
        #expect(!FileManager.default.fileExists(atPath: LumosPaths.cacheFile(environment: environment).path))
    }

    @Test func uninstallRemovesSettingsFileThatDidNotExistBefore() throws {
        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))

        _ = try SetupService.uninstall(environment: environment)

        #expect(!FileManager.default.fileExists(atPath: settingsURL.path), "must restore the pre-setup absence of settings.json")
    }

    @Test func uninstallWithNoSetupStateThrowsClearError() throws {
        do {
            _ = try SetupService.uninstall(environment: environment)
            Issue.record("expected noSetupStateFound to be thrown")
        } catch let error as SetupService.SetupError {
            guard case .noSetupStateFound = error else {
                Issue.record("expected noSetupStateFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Cache survives an ingest cycle across setup + uninstall

    @Test func uninstallRemovesCacheWrittenAfterSetup() throws {
        try writeFakeSettings(statusLineCommand: "sh /original/statusline.sh")
        _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)

        let cacheFile = LumosPaths.cacheFile(environment: environment)
        _ = try IngestService.ingest(
            input: Data("{\"session_id\":\"s1\",\"context_window\":{\"used_percentage\":10}}".utf8),
            cacheFile: cacheFile
        )
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))

        _ = try SetupService.uninstall(environment: environment)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    // MARK: - Abort-on-no-safe-backup

    @Test func abortsWithoutChangesWhenBackupCannotBeMade() throws {
        let originalData = try writeFakeSettings(statusLineCommand: "sh /original/statusline.sh")
        // Remove write permission on the directory so copyItem (the backup step) fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.path)

        do {
            _ = try SetupService.setup(environment: environment, lumosExecutablePath: fakeLumosBinaryPath)
            Issue.record("expected backupFailed to be thrown")
        } catch let error as SetupService.SetupError {
            guard case .backupFailed = error else {
                Issue.record("expected backupFailed, got \(error)")
                return
            }
        }

        // Restore permissions before asserting, otherwise reads through hardened paths could differ.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.path)

        #expect(try Data(contentsOf: settingsURL) == originalData, "settings.json must be untouched on abort")
        #expect(backupFiles().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: LumosPaths.wrapperScriptFile(environment: environment).path))
        #expect(!FileManager.default.fileExists(atPath: LumosPaths.setupStateFile(environment: environment).path))
    }
}
