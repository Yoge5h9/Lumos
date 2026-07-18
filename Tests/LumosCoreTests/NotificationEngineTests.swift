import Testing
import Foundation
@testable import LumosCore

@Suite struct NotificationEngineTests {
    // A UTC-based engine makes day/hour boundaries trivial to reason about in
    // tests: epoch hour = (t / 3600) % 24, epoch day flips every 86400s.
    private static let utc = TimeZone(identifier: "UTC")!

    private func makeEngine(tips: [Tip] = NotificationEngine.defaultTips) -> NotificationEngine {
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notifications-state.json", isDirectory: false)
        return NotificationEngine(stateFile: stateFile, tips: tips, timeZone: Self.utc)
    }

    private func date(day: Int = 0, hour: Int = 12) -> Date {
        Date(timeIntervalSince1970: Double(day) * 86_400 + Double(hour) * 3_600)
    }

    private func signal(context pct: Double?, session: String?, stale: Bool = false) -> UsageSignal {
        UsageSignal(maxContextPercentage: pct, contextSessionId: session, isStale: stale)
    }

    private let readyTiming = TimingInsight(
        hourCounts: Array(repeating: 1, count: 24),
        peakHours: [11],
        primeHour: 10,
        totalPrompts: 50,
        notEnoughData: false
    )

    // MARK: - Context

    @Test func contextFiresAtThresholdAndDeDupesPerSession() {
        let engine = makeEngine(tips: [])
        let sig = signal(context: 42, session: "sess-A")

        let first = engine.poll(now: date(), signal: sig, timing: .insufficientData)
        #expect(first?.kind == .context)
        #expect(first?.id == "context.sess-A")

        // Same session, same threshold — must not nag again (even later same day).
        let second = engine.poll(now: date(hour: 15), signal: sig, timing: .insufficientData)
        #expect(second == nil)
    }

    @Test func contextReFiresForGenuinelyNewSessionSameDay() {
        let engine = makeEngine()
        _ = engine.poll(now: date(), signal: signal(context: 55, session: "sess-A"), timing: .insufficientData)

        let newSession = engine.poll(
            now: date(hour: 16),
            signal: signal(context: 44, session: "sess-B"),
            timing: .insufficientData
        )
        #expect(newSession?.kind == .context)
        #expect(newSession?.id == "context.sess-B")
    }

    @Test func contextDoesNotFireBelowThreshold() {
        let engine = makeEngine(tips: [])
        let due = engine.poll(now: date(), signal: signal(context: 39.9, session: "sess-A"), timing: .insufficientData)
        #expect(due == nil)
    }

    @Test func contextSuppressedWhenStale() {
        let engine = makeEngine(tips: [])
        let due = engine.poll(now: date(), signal: signal(context: 88, session: "sess-A", stale: true), timing: .insufficientData)
        #expect(due == nil)
    }

    // MARK: - Daily caps

    @Test func timingCappedToOncePerDayThenFiresNextDay() {
        let engine = makeEngine(tips: [])
        let sig = signal(context: nil, session: nil)

        let first = engine.poll(now: date(day: 0, hour: 9), signal: sig, timing: readyTiming)
        #expect(first?.kind == .timing)

        let sameDay = engine.poll(now: date(day: 0, hour: 20), signal: sig, timing: readyTiming)
        #expect(sameDay == nil)

        let nextDay = engine.poll(now: date(day: 1, hour: 9), signal: sig, timing: readyTiming)
        #expect(nextDay?.kind == .timing)
    }

    @Test func tipCappedToOncePerDay() {
        let engine = makeEngine()
        let sig = signal(context: nil, session: nil)

        let first = engine.poll(now: date(day: 0, hour: 9), signal: sig, timing: .insufficientData)
        #expect(first?.kind == .tip)

        let sameDay = engine.poll(now: date(day: 0, hour: 21), signal: sig, timing: .insufficientData)
        #expect(sameDay == nil)
    }

    // MARK: - Timing cold-start

    @Test func timingSuppressedDuringColdStart() {
        let engine = makeEngine(tips: [])
        let due = engine.poll(now: date(), signal: signal(context: nil, session: nil), timing: .insufficientData)
        #expect(due == nil)
    }

    // MARK: - Quiet hours

    @Test func quietHoursSuppressEverything() {
        let engine = makeEngine()
        engine.setQuietHours(QuietHours(startHour: 22, endHour: 7))

        // 23:00 is inside the wrapping window → nothing fires.
        let quiet = engine.poll(now: date(hour: 23), signal: signal(context: 90, session: "s"), timing: readyTiming)
        #expect(quiet == nil)

        // 12:00 is outside → the Context push comes through.
        let awake = engine.poll(now: date(hour: 12), signal: signal(context: 90, session: "s"), timing: readyTiming)
        #expect(awake?.kind == .context)
    }

    // MARK: - Mute controls

    @Test func perTypeMuteSuppressesThatTypeOnly() {
        let engine = makeEngine()
        engine.setType(.context, muted: true)

        let due = engine.poll(now: date(), signal: signal(context: 90, session: "s"), timing: readyTiming)
        // Context muted, so the next-priority eligible push (Timing) surfaces instead.
        #expect(due?.kind == .timing)
    }

    @Test func perNotificationDontShowAgainSuppressesThatIdOnly() {
        let engine = makeEngine(tips: [])
        engine.dontShowAgain(id: "context.sess-A")

        let muted = engine.poll(now: date(), signal: signal(context: 90, session: "sess-A"), timing: .insufficientData)
        #expect(muted == nil)

        // A different session's Context id is unaffected.
        let other = engine.poll(now: date(hour: 13), signal: signal(context: 90, session: "sess-B"), timing: .insufficientData)
        #expect(other?.id == "context.sess-B")
    }

    // MARK: - Master off

    @Test func masterOffSuppressesEverything() {
        let engine = makeEngine()
        engine.setMasterEnabled(false)
        let due = engine.poll(now: date(), signal: signal(context: 90, session: "s"), timing: readyTiming)
        #expect(due == nil)
    }

    // MARK: - Tip rotation + seen-it

    @Test func tipsRotateWithoutRepeatUntilCycleCompletes() {
        let tips = [
            Tip(id: "t1", title: "One", body: "b1"),
            Tip(id: "t2", title: "Two", body: "b2"),
            Tip(id: "t3", title: "Three", body: "b3"),
        ]
        let engine = makeEngine(tips: tips)
        let sig = signal(context: nil, session: nil)

        var seenOrder: [String] = []
        for day in 0..<6 {
            if let due = engine.poll(now: date(day: day, hour: 9), signal: sig, timing: .insufficientData) {
                #expect(due.kind == .tip)
                seenOrder.append(due.id)
            }
        }

        // First three are the full set with no repeats; the cycle then restarts.
        #expect(Set(seenOrder.prefix(3)) == Set(["t1", "t2", "t3"]))
        #expect(seenOrder.count == 6)
        #expect(Set(seenOrder.suffix(3)) == Set(["t1", "t2", "t3"]))
    }

    @Test func mutedTipIsNeverSelected() {
        let tips = [
            Tip(id: "t1", title: "One", body: "b1"),
            Tip(id: "t2", title: "Two", body: "b2"),
        ]
        let engine = makeEngine(tips: tips)
        engine.dontShowAgain(id: "t1")
        let sig = signal(context: nil, session: nil)

        for day in 0..<4 {
            if let due = engine.poll(now: date(day: day, hour: 9), signal: sig, timing: .insufficientData) {
                #expect(due.id == "t2")
            }
        }
    }

    // MARK: - Priority

    @Test func contextOutranksTimingAndTip() {
        let engine = makeEngine()
        let due = engine.poll(now: date(), signal: signal(context: 80, session: "s"), timing: readyTiming)
        #expect(due?.kind == .context)
    }

    // MARK: - UsageSignal.fromCache

    @Test func fromCacheResolvesMaxNonStaleContextSession() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var cache: LumosCache = [:]
        cache["low"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 20),
            updatedAt: Int64(now.timeIntervalSince1970) - 5
        )
        cache["high"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 71),
            updatedAt: Int64(now.timeIntervalSince1970) - 10
        )
        cache["stale-higher"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 99),
            updatedAt: Int64(now.timeIntervalSince1970) - 10_000
        )

        let sig = UsageSignal.fromCache(cache, now: now, stalenessThreshold: 90)
        #expect(sig.maxContextPercentage == 71)
        #expect(sig.contextSessionId == "high")
        #expect(sig.isStale == false)
    }

    @Test func fromCacheReportsStaleWhenAllSessionsOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var cache: LumosCache = [:]
        cache["old"] = SessionCacheEntry(
            contextWindow: ContextWindowInfo(usedPercentage: 88),
            updatedAt: Int64(now.timeIntervalSince1970) - 10_000
        )
        let sig = UsageSignal.fromCache(cache, now: now, stalenessThreshold: 90)
        #expect(sig.isStale)
        #expect(sig.maxContextPercentage == nil)
    }

    // MARK: - State persistence

    @Test func stateSurvivesReloadAndTolerantLoadOnCorruption() throws {
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notifications-state.json", isDirectory: false)
        let engine = NotificationEngine(stateFile: stateFile, timeZone: Self.utc)

        engine.setMasterEnabled(false)
        let reloaded = NotificationEngine(stateFile: stateFile, timeZone: Self.utc)
        #expect(reloaded.currentState().masterEnabled == false)

        // Corrupt file → defaults, never a throw.
        try Data("{ not json".utf8).write(to: stateFile)
        let tolerant = NotificationEngine(stateFile: stateFile, timeZone: Self.utc)
        #expect(tolerant.currentState() == .default)
    }

    @Test func partialStateJSONDecodesWithDefaults() throws {
        let json = #"{ "master_enabled": false }"#
        let state = try JSONDecoder().decode(NotificationState.self, from: Data(json.utf8))
        #expect(state.masterEnabled == false)
        #expect(state.mutedTypes.isEmpty)
        #expect(state.seenTipIds.isEmpty)
        #expect(state.quietHours == nil)
    }
}
