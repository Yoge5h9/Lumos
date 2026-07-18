import Foundation

/// The view the app actually renders: one "current" 5h/7d snapshot plus a
/// single worst-case context percentage, derived from a cache that may hold
/// many concurrent sessions at once.
public struct CacheAggregate: Equatable {
    public struct Snapshot: Equatable {
        public let sessionId: String
        public let fiveHour: RateLimitWindow?
        public let sevenDay: RateLimitWindow?
        public let model: String?
        public let updatedAt: Int64
    }

    /// The most-recently-updated session's rate-limit snapshot, regardless of
    /// staleness — `isStale` tells the caller whether to trust it as "current".
    public let latestSnapshot: Snapshot?

    /// The highest `context_window.used_percentage` seen among sessions that
    /// are NOT stale. Stale sessions are excluded — a context percentage from
    /// a session Claude Code hasn't ticked in minutes is not "current usage".
    public let maxContextUsedPercentage: Double?

    /// True when there is no session fresh enough to trust (including "no
    /// sessions at all"). The app should show the Idle "waiting for Claude
    /// Code…" state whenever this is true.
    public let isStale: Bool
}

public enum CacheAggregator {
    /// A session is considered stale if its last update is older than this,
    /// by default — the status line goes quiet the moment Claude Code is idle
    /// or closed, so this is the freshness bar for "currently live".
    public static let defaultStalenessThreshold: TimeInterval = 90

    public static func aggregate(
        cache: LumosCache,
        now: Date = Date(),
        stalenessThreshold: TimeInterval = defaultStalenessThreshold
    ) -> CacheAggregate {
        let nowEpoch = now.timeIntervalSince1970

        func isFresh(_ updatedAt: Int64) -> Bool {
            nowEpoch - Double(updatedAt) <= stalenessThreshold
        }

        let latestEntry = cache.max { lhs, rhs in lhs.value.updatedAt < rhs.value.updatedAt }

        let latestSnapshot = latestEntry.map { sessionId, entry in
            CacheAggregate.Snapshot(
                sessionId: sessionId,
                fiveHour: entry.fiveHour,
                sevenDay: entry.sevenDay,
                model: entry.model,
                updatedAt: entry.updatedAt
            )
        }

        let isStale = !(latestEntry.map { isFresh($0.value.updatedAt) } ?? false)

        let maxContextPercentage = cache.values
            .filter { isFresh($0.updatedAt) }
            .compactMap { $0.contextWindow?.usedPercentage }
            .max()

        return CacheAggregate(
            latestSnapshot: latestSnapshot,
            maxContextUsedPercentage: maxContextPercentage,
            isStale: isStale
        )
    }

    /// Convenience: load the cache file and aggregate in one step. Any read or
    /// parse failure collapses into the same "no fresh data" result a missing
    /// file would produce — this is the entry point UI code should use.
    public static func loadAndAggregate(
        cacheFile: URL,
        now: Date = Date(),
        stalenessThreshold: TimeInterval = defaultStalenessThreshold
    ) -> CacheAggregate {
        let cache = CacheReader.loadTolerant(from: cacheFile)
        return aggregate(cache: cache, now: now, stalenessThreshold: stalenessThreshold)
    }
}
