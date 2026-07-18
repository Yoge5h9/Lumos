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
}
