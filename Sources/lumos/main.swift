import Foundation
import LumosCore
#if canImport(AppKit)
import AppKit
#endif

/// Resolves the absolute path to the currently-running `lumos` binary, so
/// `lumos setup` can embed an exact, PATH-independent path into the wrapper
/// script it writes (the script runs from Claude Code's status-line hook,
/// which may have a minimal or different PATH than the interactive shell).
func resolveExecutablePath() -> String {
    let arg0 = CommandLine.arguments.first ?? "lumos"
    let fileManager = FileManager.default

    if arg0.contains("/") {
        return URL(fileURLWithPath: arg0).standardizedFileURL.path
    }

    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        for directory in pathEnv.split(separator: ":") {
            let candidate = "\(directory)/\(arg0)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
    }

    return arg0
}

func printUsage(to handle: FileHandle) {
    let usage = """
    Usage:
      lumos ingest               Read a status-line JSON payload from stdin and cache it.
      lumos setup                Wrap the status line, start the glow, and launch at login.
      lumos setup --no-launch    Wire the status line only; don't launch or add a login item.
      lumos setup --uninstall    Restore the status line, stop Lumos, and remove its login item.
      lumos diagnose             Print notch/screen geometry Lumos resolves, then exit.
      lumos --version            Print the version and exit.

    """
    handle.write(Data(usage.utf8))
}

#if canImport(AppKit)
/// Launch the GUI menu-bar agent (this same binary, invoked with no subcommand)
/// as a detached child so it keeps running after `lumos setup` exits. stdio is
/// sent to the null device so it isn't tied to the launching terminal.
func launchGUIDetached(executablePath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = []
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
}

/// Stop any already-running GUI instances of Lumos (this executable launched
/// with no subcommand), skipping the current `setup` process itself.
func stopRunningGUI(executablePath: String) {
    let target = URL(fileURLWithPath: executablePath).standardizedFileURL
    let me = getpid()
    for app in NSWorkspace.shared.runningApplications {
        guard app.processIdentifier != me,
              let exe = app.executableURL?.standardizedFileURL,
              exe == target else { continue }
        if !app.terminate() { app.forceTerminate() }
    }
}
#endif

let arguments = Array(CommandLine.arguments.dropFirst())

if let first = arguments.first, first == "--version" || first == "-v" {
    let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    print(version)
    exit(0)
}

let knownSubcommands: Set<String> = ["ingest", "setup", "diagnose"]

guard let command = arguments.first else {
    // No subcommand → launch the menu-bar GUI agent.
    #if canImport(AppKit)
    runMenuBarAgent()
    #else
    FileHandle.standardError.write(Data("lumos: GUI requires macOS/AppKit.\n".utf8))
    exit(1)
    #endif
}

guard knownSubcommands.contains(command) else {
    printUsage(to: .standardError)
    exit(64)
}

switch command {
case "ingest":
    let input = FileHandle.standardInput.readDataToEndOfFile()
    do {
        try IngestService.ingest(input: input, cacheFile: LumosPaths.cacheFile())
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("lumos ingest: \(error)\n".utf8))
        exit(1)
    }

case "diagnose":
    #if canImport(AppKit)
    Diagnose.run()
    #else
    FileHandle.standardError.write(Data("lumos diagnose: requires macOS/AppKit.\n".utf8))
    exit(1)
    #endif

case "setup":
    let setupFlags = arguments.dropFirst()
    let isUninstall = setupFlags.contains("--uninstall")
    let noLaunch = setupFlags.contains("--no-launch")
    let executablePath = resolveExecutablePath()
    do {
        if isUninstall {
            print(try SetupService.uninstall())
            #if canImport(AppKit)
            LaunchAtLogin.setEnabled(false)
            stopRunningGUI(executablePath: executablePath)
            print("Stopped Lumos and removed it from your login items.")
            #endif
        } else {
            print(try SetupService.setup(lumosExecutablePath: executablePath))
            #if canImport(AppKit)
            if !noLaunch {
                LaunchAtLogin.setEnabled(true) // soft-fails on an unbundled dev binary
                launchGUIDetached(executablePath: executablePath)
                print("Lumos is running — look at your notch.")
            }
            #endif
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("lumos setup: \(error)\n".utf8))
        exit(1)
    }

default:
    printUsage(to: .standardError)
    exit(64)
}
