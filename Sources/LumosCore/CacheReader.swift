import Foundation

/// Reads the on-disk Lumos cache. A missing file is a normal, expected state
/// (Lumos hasn't been wired up yet, or no session has ticked since install) —
/// callers get an empty cache rather than an error.
public enum CacheReader {
    public enum CacheReadError: Error, CustomStringConvertible {
        case malformed(underlying: Error)

        public var description: String {
            switch self {
            case .malformed(let underlying):
                return "cache file is not valid Lumos cache JSON: \(underlying)"
            }
        }
    }

    /// Loads the cache from disk. Returns an empty cache if the file doesn't exist.
    /// Throws only when the file exists but cannot be parsed — a genuinely
    /// corrupt cache, distinct from "no data yet".
    public static func load(from url: URL) throws -> LumosCache {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Unreadable (permissions, race with a concurrent delete, etc.) is
            // treated the same as "no data yet" — never crash the caller.
            return [:]
        }
        if data.isEmpty {
            return [:]
        }
        do {
            return try JSONDecoder().decode(LumosCache.self, from: data)
        } catch {
            throw CacheReadError.malformed(underlying: error)
        }
    }

    /// Loads the cache, collapsing any read/parse failure into "no data yet"
    /// rather than propagating an error. Use this from UI-facing call sites
    /// that must never crash on a corrupt or half-written cache file.
    public static func loadTolerant(from url: URL) -> LumosCache {
        (try? load(from: url)) ?? [:]
    }
}
