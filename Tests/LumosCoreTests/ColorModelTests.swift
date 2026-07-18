import Testing
import Foundation
@testable import LumosCore

@Suite struct ColorModelTests {
    // A comfortable amount of runway so tests aren't accidentally in the
    // reset-imminent relaxation window.
    let hoursLeft: Double = 3 * 3600

    // MARK: - State → hex / rgb mapping

    @Test func stateHexMapping() {
        #expect(UsageState.calm.hex == "#30D158")
        #expect(UsageState.watch.hex == "#FFD60A")
        #expect(UsageState.alert.hex == "#FF453A")
        #expect(UsageState.idle.hex == "#8C8C8C")
    }

    @Test func stateRgbMatchesHex() {
        let (r, g, b) = UsageState.calm.rgb
        #expect(abs(r - 0x30 / 255.0) < 1e-9)
        #expect(abs(g - 0xD1 / 255.0) < 1e-9)
        #expect(abs(b - 0x58 / 255.0) < 1e-9)

        let idle = UsageState.idle.rgb
        #expect(abs(idle.red - 0x8C / 255.0) < 1e-9)
        #expect(idle.red == idle.green && idle.green == idle.blue)
    }

    // MARK: - The permanent regression check

    @Test func freshWindowIsNeverAlert() {
        // 2% used, hours left — Calm no matter what.
        #expect(ColorModel.state(usedPercentage: 2, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .calm)

        // Even with an absurdly high burn-rate injected, the <45% gate keeps a
        // fresh window Calm. This is the permanent False-Alert regression guard.
        let absurdBurn = 1.0 // 100%/s
        #expect(ColorModel.state(usedPercentage: 2, timeLeftSeconds: hoursLeft, burnRatePerSecond: absurdBurn) == .calm)
    }

    // MARK: - Raw-depletion thresholds

    @Test func calmWatchBoundaryAt45() {
        #expect(ColorModel.state(usedPercentage: 44.9, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .calm)
        #expect(ColorModel.state(usedPercentage: 45, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .watch)
    }

    @Test func midWindowSteadyIsWatch() {
        // ~60%, a few hours left, no meaningful burn → Watch.
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .watch)
    }

    @Test func nearLimitIsAlert() {
        #expect(ColorModel.state(usedPercentage: 89.9, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .watch)
        #expect(ColorModel.state(usedPercentage: 90, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .alert)
        #expect(ColorModel.state(usedPercentage: 95, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .alert)
    }

    // MARK: - Burn escalation & the 45→75 ramp

    @Test func burnBelowGateCannotEscalate() {
        // 44% used with a burn that would blow past 100% — gate is shut → Calm.
        #expect(ColorModel.state(usedPercentage: 44, timeLeftSeconds: hoursLeft, burnRatePerSecond: 1.0) == .calm)
    }

    @Test func burningFastEscalatesWatchToAlert() {
        // 60% used, burn high enough that the gated projection crosses 100%.
        // gate(0.60) = (0.60-0.45)/0.30 = 0.5; timeLeft = 10800s.
        // Need used + 0.5 * burn * 10800 >= 1.0  →  burn >= 0.4/5400 ≈ 7.41e-5.
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: hoursLeft, burnRatePerSecond: 1e-4) == .alert)
        // A gentle burn that won't run the window dry → stays Watch.
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: hoursLeft, burnRatePerSecond: 1e-6) == .watch)
    }

    @Test func gateRampWeightsBurnByUsage() {
        #expect(ColorModel.escalationGate(0.45) == 0)
        #expect(ColorModel.escalationGate(0.30) == 0)
        #expect(abs(ColorModel.escalationGate(0.60) - 0.5) < 1e-9)
        #expect(ColorModel.escalationGate(0.75) == 1)
        #expect(ColorModel.escalationGate(0.90) == 1)
    }

    // MARK: - Reset-imminent relaxation

    @Test func nearLimitRelaxesWhenResetImminent() {
        // 95% used but reset in 5 minutes — refill imminent → relax to Watch.
        #expect(ColorModel.state(usedPercentage: 95, timeLeftSeconds: 5 * 60, burnRatePerSecond: nil) == .watch)
        // Just outside the imminent window → still Alert.
        #expect(ColorModel.state(usedPercentage: 95, timeLeftSeconds: 20 * 60, burnRatePerSecond: nil) == .alert)
    }

    // MARK: - Idle: stale / missing / passed reset

    @Test func missingUsageIsIdle() {
        #expect(ColorModel.state(usedPercentage: nil, timeLeftSeconds: hoursLeft, burnRatePerSecond: nil) == .idle)
    }

    @Test func missingOrPassedResetIsIdle() {
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: nil, burnRatePerSecond: nil) == .idle)
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: 0, burnRatePerSecond: nil) == .idle)
        #expect(ColorModel.state(usedPercentage: 60, timeLeftSeconds: -30, burnRatePerSecond: nil) == .idle)
    }

    @Test func staleAggregateIsIdle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let aggregate = CacheAggregate(
            latestSnapshot: CacheAggregate.Snapshot(
                sessionId: "s",
                fiveHour: RateLimitWindow(usedPercentage: 95, resetsAt: 1_100_000),
                sevenDay: nil,
                model: nil,
                updatedAt: Int64(now.timeIntervalSince1970)
            ),
            maxContextUsedPercentage: nil,
            isStale: true
        )
        #expect(ColorModel.state(aggregate: aggregate, now: now) == .idle)
    }

    @Test func aggregateConvenienceReadsFiveHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let aggregate = CacheAggregate(
            latestSnapshot: CacheAggregate.Snapshot(
                sessionId: "s",
                fiveHour: RateLimitWindow(usedPercentage: 60, resetsAt: Int64(now.timeIntervalSince1970) + 3 * 3600),
                sevenDay: nil,
                model: nil,
                updatedAt: Int64(now.timeIntervalSince1970)
            ),
            maxContextUsedPercentage: nil,
            isStale: false
        )
        #expect(ColorModel.state(aggregate: aggregate, now: now) == .watch)
    }

    // MARK: - Burn-rate sampler

    @Test func samplerNeedsAtLeastThreeSamples() {
        var sampler = BurnRateSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        sampler.record(usedPercentage: 10, at: t0)
        sampler.record(usedPercentage: 20, at: t0.addingTimeInterval(900))
        // Only two samples, even over a long span → no rate.
        #expect(sampler.burnRatePerSecond() == nil)
    }

    @Test func samplerNeedsTenMinuteSpan() {
        var sampler = BurnRateSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        sampler.record(usedPercentage: 10, at: t0)
        sampler.record(usedPercentage: 12, at: t0.addingTimeInterval(120))
        sampler.record(usedPercentage: 14, at: t0.addingTimeInterval(300))
        // Three samples but only 5 minutes → not yet trusted.
        #expect(sampler.burnRatePerSecond() == nil)
    }

    @Test func samplerComputesSlopeOverEnoughSignal() {
        var sampler = BurnRateSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        // Collinear: +10 percentage points (0.10 fraction) over 1000s.
        sampler.record(usedPercentage: 50, at: t0)
        sampler.record(usedPercentage: 55, at: t0.addingTimeInterval(500))
        sampler.record(usedPercentage: 60, at: t0.addingTimeInterval(1000))
        let rate = try! #require(sampler.burnRatePerSecond())
        #expect(abs(rate - 0.10 / 1000.0) < 1e-12)
    }

    @Test func samplerFeedsColorModelEndToEnd() {
        var sampler = BurnRateSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        // Steep climb while already deep in the window.
        sampler.record(usedPercentage: 70, at: t0)
        sampler.record(usedPercentage: 78, at: t0.addingTimeInterval(600))
        sampler.record(usedPercentage: 86, at: t0.addingTimeInterval(1200))
        let rate = try! #require(sampler.burnRatePerSecond())
        // At 86% used with a couple of hours left, that climb runs it dry → Alert.
        #expect(ColorModel.state(usedPercentage: 86, timeLeftSeconds: 2 * 3600, burnRatePerSecond: rate) == .alert)
    }
}
