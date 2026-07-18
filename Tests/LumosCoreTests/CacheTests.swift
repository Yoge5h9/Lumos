import Testing
import Foundation
@testable import LumosCore

@Suite struct CacheTests {
    @Test func decodesFullEntry() throws {
        let json = """
        {
          "sess-1": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 },
            "context_window": { "used_percentage": 38, "context_window_size": 200000 },
            "model": "claude-opus-4-8",
            "updated_at": 1738371243
          }
        }
        """
        let cache = try JSONDecoder().decode(LumosCache.self, from: Data(json.utf8))
        let entry = try #require(cache["sess-1"])
        #expect(entry.fiveHour?.usedPercentage == 23.5)
        #expect(entry.fiveHour?.resetsAt == 1738425600)
        #expect(entry.sevenDay?.usedPercentage == 41.2)
        #expect(entry.contextWindow?.usedPercentage == 38)
        #expect(entry.contextWindow?.contextWindowSize == 200000)
        #expect(entry.model == "claude-opus-4-8")
        #expect(entry.updatedAt == 1738371243)
    }

    @Test func missingRateLimitsDecodesAsNil() throws {
        let json = """
        {
          "sess-free-plan": {
            "context_window": { "used_percentage": 12.0, "context_window_size": 200000 },
            "updated_at": 1738371243
          }
        }
        """
        let cache = try JSONDecoder().decode(LumosCache.self, from: Data(json.utf8))
        let entry = try #require(cache["sess-free-plan"])
        #expect(entry.fiveHour == nil)
        #expect(entry.sevenDay == nil)
        #expect(entry.contextWindow?.usedPercentage == 12.0)
    }

    @Test func nullContextUsedPercentageDecodesAsNil() throws {
        let json = """
        {
          "sess-fresh": {
            "context_window": { "used_percentage": null, "context_window_size": 200000 },
            "updated_at": 1738371243
          }
        }
        """
        let cache = try JSONDecoder().decode(LumosCache.self, from: Data(json.utf8))
        let entry = try #require(cache["sess-fresh"])
        #expect(entry.contextWindow != nil)
        #expect(entry.contextWindow?.usedPercentage == nil)
    }

    @Test func aggregatePicksLatestSnapshotAndMaxNonStaleContext() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threshold: TimeInterval = 90

        var cache: LumosCache = [:]
        // Fresh, most recently updated — should become the latest snapshot.
        cache["fresh-latest"] = SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: 50, resetsAt: 1_100_000),
            sevenDay: RateLimitWindow(usedPercentage: 10, resetsAt: 1_600_000),
            contextWindow: ContextWindowInfo(usedPercentage: 20, contextWindowSize: 200_000),
            model: "claude-opus-4-8",
            updatedAt: Int64(now.timeIntervalSince1970) - 5
        )
        // Fresh, but updated slightly earlier — has the highest context %.
        cache["fresh-high-context"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 77, contextWindowSize: 200_000),
            updatedAt: Int64(now.timeIntervalSince1970) - 30
        )
        // Stale — must be excluded from both latest-snapshot and max-context.
        cache["stale"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 99, contextWindowSize: 200_000),
            updatedAt: Int64(now.timeIntervalSince1970) - 10_000
        )

        let aggregate = CacheAggregator.aggregate(cache: cache, now: now, stalenessThreshold: threshold)

        #expect(aggregate.latestSnapshot?.sessionId == "fresh-latest")
        #expect(aggregate.latestSnapshot?.fiveHour?.usedPercentage == 50)
        #expect(aggregate.isStale == false)
        #expect(aggregate.maxContextUsedPercentage == 77, "must ignore the stale session's higher 99%")
    }

    @Test func allStaleSessionsProduceNoFreshData() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var cache: LumosCache = [:]
        cache["stale-only"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 55),
            updatedAt: Int64(now.timeIntervalSince1970) - 10_000
        )

        let aggregate = CacheAggregator.aggregate(cache: cache, now: now, stalenessThreshold: 90)

        #expect(aggregate.isStale)
        #expect(aggregate.maxContextUsedPercentage == nil)
        // latestSnapshot itself is still surfaced (stale, but present) so the
        // caller could show "last seen" info if it ever wants to.
        #expect(aggregate.latestSnapshot?.sessionId == "stale-only")
    }

    @Test func missingCacheFileGivesNoFreshData() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cache.json")

        let aggregate = CacheAggregator.loadAndAggregate(cacheFile: missingURL)

        #expect(aggregate.isStale)
        #expect(aggregate.latestSnapshot == nil)
        #expect(aggregate.maxContextUsedPercentage == nil)
    }

    @Test func emptyCacheIsNotACrash() throws {
        let cache = try JSONDecoder().decode(LumosCache.self, from: Data("{}".utf8))
        #expect(cache.isEmpty)
        let aggregate = CacheAggregator.aggregate(cache: cache)
        #expect(aggregate.isStale)
    }

    // MARK: - Freshness tiers

    @Test func staleProSessionIsStaleNotLiveNorRefilled() {
        // Mirrors a real multi-session cache: the latest snapshot is a Pro/Max
        // session last ticked ~52m ago with reset still hours out. It must read
        // .stale (frozen numbers), never .live and never .refilled.
        let now = Date(timeIntervalSince1970: 1_784_390_297)
        var cache: LumosCache = [:]
        cache["older"] = SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: 65, resetsAt: 1_784_386_800),
            updatedAt: 1_784_381_223
        )
        cache["latest"] = SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: 2, resetsAt: 1_784_404_800),
            updatedAt: 1_784_387_163
        )
        let aggregate = CacheAggregator.aggregate(cache: cache, now: now)
        #expect(aggregate.latestSnapshot?.sessionId == "latest")
        #expect(aggregate.freshness(now: now) == .stale)
    }

    @Test func recentlyPassedResetIsRefilled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var cache: LumosCache = [:]
        cache["s"] = SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: 80, resetsAt: 999_000),
            updatedAt: 990_000
        )
        // Reset just behind now, next window boundary still ahead → refilled.
        #expect(CacheAggregator.aggregate(cache: cache, now: now).freshness(now: now) == .refilled)
    }

    @Test func ancientPastResetCollapsesToWaitingNotRefilled() {
        // Reset is so far behind that even the next window boundary
        // (reset + one 5h window) is already past — an ancient snapshot must not
        // masquerade as a bright refill with a nonsense 0m countdown.
        let resetsAt: Int64 = 1_000_000
        let now = Date(timeIntervalSince1970:
            TimeInterval(resetsAt + CacheAggregator.fiveHourWindowSeconds + 60))
        var cache: LumosCache = [:]
        cache["ancient"] = SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: 80, resetsAt: resetsAt),
            updatedAt: 990_000
        )
        #expect(CacheAggregator.aggregate(cache: cache, now: now).freshness(now: now) == .waiting)
    }

    @Test func effectiveFreshnessPolicy() {
        // Master-off silences everything.
        #expect(Freshness.effective(raw: .live, state: .calm, masterOff: true) == .waiting)
        // Stale with no numbers to freeze (Idle) → waiting, not a frozen stale.
        #expect(Freshness.effective(raw: .stale, state: .idle, masterOff: false) == .waiting)
        // Stale WITH numbers (e.g. Calm) stays stale — the notch/menu/LED agree.
        #expect(Freshness.effective(raw: .stale, state: .calm, masterOff: false) == .stale)
        // Everything else passes through untouched.
        #expect(Freshness.effective(raw: .refilled, state: .calm, masterOff: false) == .refilled)
        #expect(Freshness.effective(raw: .live, state: .watch, masterOff: false) == .live)
    }
}
