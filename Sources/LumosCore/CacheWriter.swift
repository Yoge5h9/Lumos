import Foundation

/// Mutates and persists the Lumos cache. Kept separate from `CacheReader` since
/// only `lumos ingest` ever writes — every other consumer is read-only.
public enum CacheWriter {
    /// Sessions untouched for longer than this are dropped on the next write —
    /// keeps the cache bounded across long-running machines with many
    /// short-lived Claude Code sessions over weeks.
    public static let defaultPruneAge: TimeInterval = 14 * 24 * 60 * 60

    public static func upsert(_ entry: SessionCacheEntry, forSession sessionId: String, into cache: inout LumosCache) {
        cache[sessionId] = entry
    }

    public static func pruneStaleSessions(_ cache: inout LumosCache, olderThan maxAge: TimeInterval = defaultPruneAge, now: Date = Date()) {
        let nowEpoch = now.timeIntervalSince1970
        cache = cache.filter { nowEpoch - Double($0.value.updatedAt) <= maxAge }
    }

    public static func write(_ cache: LumosCache, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cache)
        try AtomicFile.write(data, to: url)
    }
}
