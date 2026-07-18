import Testing
import Foundation
@testable import LumosCore

/// The freshness/aggregate transitions the running app must reflect live when the
/// cache changes underneath it (no relaunch). These pin the pure logic the notch
/// paint pipeline depends on; the vnode-watch plumbing that feeds it is exercised
/// by `scripts/test-live-update.sh`.
@Suite struct LiveUpdateTests {
    private let threshold = CacheAggregator.defaultStalenessThreshold

    private func entry(used: Double, updatedAt: Int64, resetsAt: Int64) -> SessionCacheEntry {
        SessionCacheEntry(
            fiveHour: RateLimitWindow(usedPercentage: used, resetsAt: resetsAt),
            sevenDay: RateLimitWindow(usedPercentage: 40, resetsAt: resetsAt + 20_000),
            contextWindow: ContextWindowInfo(usedPercentage: 22, contextWindowSize: 200_000),
            model: "Sonnet 5",
            updatedAt: updatedAt
        )
    }

    @Test func emptyCacheIsWaitingThenFirstDataIsLive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let nowEpoch = Int64(now.timeIntervalSince1970)

        let empty = CacheAggregator.aggregate(cache: [:], now: now)
        #expect(empty.freshness(now: now) == .waiting)

        let cache: LumosCache = ["s": entry(used: 36, updatedAt: nowEpoch, resetsAt: nowEpoch + 7_000)]
        let live = CacheAggregator.aggregate(cache: cache, now: now)
        #expect(live.freshness(now: now) == .live)
        #expect(live.latestSnapshot?.fiveHour?.usedPercentage == 36)
    }

    @Test func liveBecomesStaleAsClockAdvances() {
        let updatedAt: Int64 = 1_000_000
        let cache: LumosCache = ["s": entry(used: 36, updatedAt: updatedAt, resetsAt: updatedAt + 7_000)]

        let fresh = Date(timeIntervalSince1970: TimeInterval(updatedAt) + 10)
        #expect(CacheAggregator.aggregate(cache: cache, now: fresh).freshness(now: fresh) == .live)

        let aged = Date(timeIntervalSince1970: TimeInterval(updatedAt) + threshold + 1)
        #expect(CacheAggregator.aggregate(cache: cache, now: aged).freshness(now: aged) == .stale)
    }

    @Test func staleBecomesLiveOnNewWrite() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let nowEpoch = Int64(now.timeIntervalSince1970)

        let old: LumosCache = ["s": entry(used: 36, updatedAt: nowEpoch - Int64(threshold) - 60,
                                          resetsAt: nowEpoch + 7_000)]
        #expect(CacheAggregator.aggregate(cache: old, now: now).freshness(now: now) == .stale)

        let refreshed: LumosCache = ["s": entry(used: 52, updatedAt: nowEpoch, resetsAt: nowEpoch + 7_000)]
        let live = CacheAggregator.aggregate(cache: refreshed, now: now)
        #expect(live.freshness(now: now) == .live)
        #expect(live.latestSnapshot?.fiveHour?.usedPercentage == 52)
    }

    @Test func crossingResetBoundaryBecomesRefilled() {
        let resetsAt: Int64 = 1_000_000
        let cache: LumosCache = ["s": entry(used: 80, updatedAt: resetsAt - 5_000, resetsAt: resetsAt)]

        let before = Date(timeIntervalSince1970: TimeInterval(resetsAt) - 60)
        #expect(CacheAggregator.aggregate(cache: cache, now: before).freshness(now: before) == .live)

        let after = Date(timeIntervalSince1970: TimeInterval(resetsAt) + 60)
        #expect(CacheAggregator.aggregate(cache: cache, now: after).freshness(now: after) == .refilled)
    }

    @Test func corruptCacheFileIsToleratedAsNoData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cache.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A half-written cache (mid atomic rename) must never crash the reader.
        try Data("{ this is not json".utf8).write(to: url)

        let aggregate = CacheAggregator.loadAndAggregate(cacheFile: url)
        #expect(aggregate.latestSnapshot == nil)
        #expect(aggregate.freshness() == .waiting)
    }

    @Test func deletedCacheReturnsToWaitingThenRepopulates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cache.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        let nowEpoch = Int64(now.timeIntervalSince1970)

        let cache: LumosCache = ["s": entry(used: 36, updatedAt: nowEpoch, resetsAt: nowEpoch + 7_000)]
        try AtomicFile.write(try JSONEncoder().encode(cache), to: url)
        #expect(CacheAggregator.loadAndAggregate(cacheFile: url, now: now).freshness(now: now) == .live)

        try FileManager.default.removeItem(at: url)
        #expect(CacheAggregator.loadAndAggregate(cacheFile: url, now: now).freshness(now: now) == .waiting)

        try AtomicFile.write(try JSONEncoder().encode(cache), to: url)
        #expect(CacheAggregator.loadAndAggregate(cacheFile: url, now: now).freshness(now: now) == .live)
    }

    @Test func multiSessionPicksLatestForLiveReading() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let nowEpoch = Int64(now.timeIntervalSince1970)
        let cache: LumosCache = [
            "older": entry(used: 20, updatedAt: nowEpoch - 40, resetsAt: nowEpoch + 7_000),
            "latest": entry(used: 71, updatedAt: nowEpoch - 2, resetsAt: nowEpoch + 7_000),
        ]
        let aggregate = CacheAggregator.aggregate(cache: cache, now: now)
        #expect(aggregate.latestSnapshot?.sessionId == "latest")
        #expect(aggregate.latestSnapshot?.fiveHour?.usedPercentage == 71)
        #expect(aggregate.freshness(now: now) == .live)
    }
}
