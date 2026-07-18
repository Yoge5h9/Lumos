import Foundation

/// Writes files the way anything that shares state with a concurrently-running
/// process must: to a sibling temp file, then renamed into place, so a reader
/// never observes a half-written file.
public enum AtomicFile {
    public enum AtomicFileError: Error, CustomStringConvertible {
        case directoryCreationFailed(URL, underlying: Error)
        case writeFailed(URL, underlying: Error)
        case renameFailed(from: URL, to: URL, underlying: Error)

        public var description: String {
            switch self {
            case .directoryCreationFailed(let url, let underlying):
                return "could not create directory at \(url.path): \(underlying)"
            case .writeFailed(let url, let underlying):
                return "could not write temp file at \(url.path): \(underlying)"
            case .renameFailed(let from, let to, let underlying):
                return "could not move \(from.path) into place at \(to.path): \(underlying)"
            }
        }
    }

    public static func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw AtomicFileError.directoryCreationFailed(directory, underlying: error)
        }

        // A per-writer temp name (pid + uuid) so two processes ingesting the same
        // cache concurrently never share one temp file and corrupt each other's
        // partial write before the atomic rename.
        let tempName = "\(destination.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName, isDirectory: false)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw AtomicFileError.writeFailed(tempURL, underlying: error)
        }

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            // replaceItemAt requires the destination to exist on some filesystems' edge
            // cases; fall back to a plain move for the create case.
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
            } catch {
                throw AtomicFileError.renameFailed(from: tempURL, to: destination, underlying: error)
            }
        }
    }
}
