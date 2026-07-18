import Foundation

/// The three kinds of push Lumos can surface, each independently controllable.
public enum NotificationKind: String, Codable, CaseIterable, Equatable {
    case context
    case timing
    case tip
}

/// A single notification the UI should render as the notch/fallback pill. `id`
/// is stable per notification instance so "don't show again" can target it, and
/// so the same push is never enqueued twice.
public struct DueNotification: Equatable {
    public let kind: NotificationKind
    public let id: String
    public let title: String
    public let body: String

    public init(kind: NotificationKind, id: String, title: String, body: String) {
        self.kind = kind
        self.id = id
        self.title = title
        self.body = body
    }
}

/// A rotating pro-tip. The list is an updatable static default; each tip keeps a
/// stable `id` so "seen-it" memory and per-tip muting survive list edits.
/// `Codable` so tips can also be loaded from the bundled `tips.json` at launch.
public struct Tip: Codable, Equatable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// A quiet-hours window expressed in whole local hours. `[startHour, endHour)`,
/// wrapping past midnight when `startHour > endHour`. Equal bounds mean "no quiet
/// hours" (an empty window) rather than "all day".
public struct QuietHours: Codable, Equatable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public func contains(hour: Int) -> Bool {
        let h = ((hour % 24) + 24) % 24
        guard startHour != endHour else { return false }
        if startHour < endHour {
            return h >= startHour && h < endHour
        }
        return h >= startHour || h < endHour
    }
}

/// Everything the engine persists between runs. Decoding is tolerant per field:
/// any absent OR wrong-typed field falls back to its default, so an older or
/// partially-corrupt state file still loads — and the fields that ARE valid
/// (notably master-off and quiet-hours) are never lost because one other field
/// was garbled. Only a non-object top-level falls back to a full default.
public struct NotificationState: Codable, Equatable {
    public var masterEnabled: Bool
    /// Per-type "don't show again", keyed by `NotificationKind.rawValue`.
    public var mutedTypes: Set<String>
    /// Per-notification "don't show again", keyed by `DueNotification.id`.
    public var mutedIds: Set<String>
    /// Last calendar day (yyyy-MM-dd, configured time zone) a type was shown,
    /// keyed by `NotificationKind.rawValue`. Enforces the ~1/day cap for
    /// Timing and Tip. Context does not use this — it de-dupes per session.
    public var lastShownDay: [String: String]
    /// Session ids a Context push has already fired for, so it never nags twice
    /// for the same session while still re-firing for a genuinely new one.
    public var contextSeenSessions: Set<String>
    /// Tip ids shown in the current rotation cycle; reset when the cycle completes.
    public var seenTipIds: Set<String>
    public var quietHours: QuietHours?

    public init(
        masterEnabled: Bool = true,
        mutedTypes: Set<String> = [],
        mutedIds: Set<String> = [],
        lastShownDay: [String: String] = [:],
        contextSeenSessions: Set<String> = [],
        seenTipIds: Set<String> = [],
        quietHours: QuietHours? = nil
    ) {
        self.masterEnabled = masterEnabled
        self.mutedTypes = mutedTypes
        self.mutedIds = mutedIds
        self.lastShownDay = lastShownDay
        self.contextSeenSessions = contextSeenSessions
        self.seenTipIds = seenTipIds
        self.quietHours = quietHours
    }

    public static let `default` = NotificationState()

    enum CodingKeys: String, CodingKey {
        case masterEnabled = "master_enabled"
        case mutedTypes = "muted_types"
        case mutedIds = "muted_ids"
        case lastShownDay = "last_shown_day"
        case contextSeenSessions = "context_seen_sessions"
        case seenTipIds = "seen_tip_ids"
        case quietHours = "quiet_hours"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        masterEnabled = (try? c.decode(Bool.self, forKey: .masterEnabled)) ?? true
        mutedTypes = (try? c.decode(Set<String>.self, forKey: .mutedTypes)) ?? []
        mutedIds = (try? c.decode(Set<String>.self, forKey: .mutedIds)) ?? []
        lastShownDay = (try? c.decode([String: String].self, forKey: .lastShownDay)) ?? [:]
        contextSeenSessions = (try? c.decode(Set<String>.self, forKey: .contextSeenSessions)) ?? []
        seenTipIds = (try? c.decode(Set<String>.self, forKey: .seenTipIds)) ?? []
        quietHours = try? c.decode(QuietHours.self, forKey: .quietHours)
    }
}

/// The usage input the engine reasons about: the highest context percentage
/// across live (non-stale) sessions and the session that owns it, plus whether
/// there's any fresh data at all. Resolving the owning session here (not just
/// the max value) is what lets Context de-dupe correctly per session.
public struct UsageSignal: Equatable {
    public let maxContextPercentage: Double?
    public let contextSessionId: String?
    public let isStale: Bool

    public init(maxContextPercentage: Double?, contextSessionId: String?, isStale: Bool) {
        self.maxContextPercentage = maxContextPercentage
        self.contextSessionId = contextSessionId
        self.isStale = isStale
    }

    /// Correct signal: finds the non-stale session with the highest context
    /// percentage, mirroring `CacheAggregator`'s freshness rule so Context keys
    /// its de-dupe on the session actually filling up (not merely the latest).
    public static func fromCache(
        _ cache: LumosCache,
        now: Date,
        stalenessThreshold: TimeInterval = CacheAggregator.defaultStalenessThreshold
    ) -> UsageSignal {
        let aggregate = CacheAggregator.aggregate(cache: cache, now: now, stalenessThreshold: stalenessThreshold)
        return UsageSignal(
            maxContextPercentage: aggregate.maxContextUsedPercentage,
            contextSessionId: aggregate.contextSessionId,
            isStale: aggregate.isStale
        )
    }
}

/// The calm-contract notification brain. Pure decision logic (`evaluate`) is
/// separated from disk I/O (`poll`, mutators) so the whole contract is testable
/// with hand-built state and an injected clock — no `Date()` is read internally.
public final class NotificationEngine {
    /// Context quality starts dipping past this used-percentage.
    public static let contextThreshold: Double = 40

    /// Reset time and all day/hour boundaries are computed in IST for now
    /// (matches the Readout's hardcoded IST reset display).
    public static let defaultTimeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current

    public static func defaultStateFile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        LumosPaths.cacheDir(environment: environment)
            .appendingPathComponent("notifications-state.json", isDirectory: false)
    }

    /// Tip content ships as `tips.json` in the app bundle's `Resources/` so it can be
    /// refreshed by editing that file (see `packaging/homebrew-lumos/README.md`)
    /// without a Swift rebuild. Any failure to find, read, or parse it — including a
    /// raw `swift build` dev run, which has no `.app` bundle at all — falls back to
    /// the embedded `defaultTips` so the engine always has a tip list.
    public static func loadTips(bundle: Bundle = .main) -> [Tip] {
        guard let url = bundle.url(forResource: "tips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Tip].self, from: data),
              !decoded.isEmpty
        else {
            return defaultTips
        }
        return decoded
    }

    /// Embedded fallback, also the historical/canonical tip set that `tips.json` is
    /// seeded from.
    public static let defaultTips: [Tip] = [
        Tip(id: "tip.compact",
            title: "Keep context crisp",
            body: "Long session getting heavy? /compact summarizes the thread and frees up context."),
        Tip(id: "tip.handoff",
            title: "Hand off, don't hoard",
            body: "Near a context limit? Write a short handoff note and start a fresh session — quality holds up better."),
        Tip(id: "tip.resume",
            title: "Pick up where you left off",
            body: "claude --resume reopens a past session so you don't lose the thread across a break."),
        Tip(id: "tip.clear",
            title: "Start clean between tasks",
            body: "Switching to an unrelated task? /clear gives Claude a fresh slate and a lighter context."),
        Tip(id: "tip.prime",
            title: "Time your window",
            body: "Your 5-hour window starts on first use — kick it off just before your busy stretch to cover it fully."),
        Tip(id: "tip.plan",
            title: "Think before building",
            body: "Ask for a plan first on a big change, review it, then let Claude execute — fewer wrong turns."),
        Tip(id: "tip.subagent",
            title: "Offload to a subagent",
            body: "Big search or side task? A subagent runs in its own context so your main thread stays lean."),
        Tip(id: "tip.cowork",
            title: "Meet Cowork",
            body: "Claude's agentic workspace for non-coding work — research, docs, spreadsheets. Describe the outcome, step away, come back to finished work."),
        // Time-sensitive: the Cowork usage boost is reported to end ~Aug 2026 and is not
        // confirmed by a primary Anthropic source — phrased softly on purpose. Soften further
        // or drop this tip if the promo has lapsed by the time Lumos ships.
        Tip(id: "tip.cowork-boost",
            title: "Cowork has extra usage right now",
            body: "For a limited time, Cowork's 5-hour limit is boosted on paid plans — a good moment to try agentic work. Check claude.ai for current limits."),
        Tip(id: "tip.chrome",
            title: "Claude in your browser",
            body: "Claude for Chrome is a sidebar agent that can see and click pages — navigate, fill forms, pull data. Needs a paid plan."),
        Tip(id: "tip.chrome-replay",
            title: "Record once, replay later",
            body: "Show Claude for Chrome a browser task once and it can rerun it on a schedule — daily, weekly, monthly."),
        Tip(id: "tip.remote",
            title: "Drive Claude Code from your phone",
            body: "Remote Control lets your phone send a task to a Claude Code session on your Mac and check progress on the go."),
        Tip(id: "tip.artifacts",
            title: "Replies become mini-apps",
            body: "Artifacts turn a Claude answer into a live, shareable preview — code, HTML, diagrams, React — on every plan."),
    ]

    private let stateFile: URL
    private let tips: [Tip]
    private let timeZone: TimeZone
    private let calendar: Calendar
    private let dayFormatter: DateFormatter

    public init(
        stateFile: URL? = nil,
        tips: [Tip] = NotificationEngine.loadTips(),
        timeZone: TimeZone = NotificationEngine.defaultTimeZone,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.stateFile = stateFile ?? NotificationEngine.defaultStateFile(environment: environment)
        self.tips = tips
        self.timeZone = timeZone

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = fmt
    }

    // MARK: - Pure decision

    /// Decides which single notification (if any) is due now, given fully
    /// resolved inputs and the current persisted state. No side effects — the
    /// caller records the result (see `record` / `poll`). Priority when several
    /// are eligible: Context (time-sensitive) → Timing → Tip.
    public func evaluate(
        now: Date,
        signal: UsageSignal,
        timing: TimingInsight,
        state: NotificationState
    ) -> DueNotification? {
        guard state.masterEnabled else { return nil }

        let hour = calendar.component(.hour, from: now)
        if let quiet = state.quietHours, quiet.contains(hour: hour) { return nil }

        let today = dayFormatter.string(from: now)

        if let context = contextCandidate(signal: signal, state: state) { return context }
        if let timingPush = timingCandidate(timing: timing, state: state, today: today) { return timingPush }
        if let tip = tipCandidate(state: state, today: today) { return tip }
        return nil
    }

    /// Applies a shown notification to `state`: marks daily caps, remembers the
    /// session for Context, and advances Tip rotation (resetting the cycle when
    /// every non-muted tip has been seen).
    public func record(_ due: DueNotification, at now: Date, into state: inout NotificationState) {
        let today = dayFormatter.string(from: now)
        switch due.kind {
        case .context:
            if let sessionId = sessionId(fromContextId: due.id) {
                state.contextSeenSessions.insert(sessionId)
            }
        case .timing:
            state.lastShownDay[NotificationKind.timing.rawValue] = today
        case .tip:
            state.lastShownDay[NotificationKind.tip.rawValue] = today
            var seen = state.seenTipIds
            seen.insert(due.id)
            let selectable = Set(tips.map(\.id)).subtracting(state.mutedIds)
            if !selectable.isEmpty, selectable.isSubset(of: seen) {
                seen = []
            }
            state.seenTipIds = seen
        }
    }

    // MARK: - Candidates

    private func contextCandidate(signal: UsageSignal, state: NotificationState) -> DueNotification? {
        guard !state.isTypeMuted(.context) else { return nil }
        guard !signal.isStale else { return nil }
        guard let pct = signal.maxContextPercentage, pct >= Self.contextThreshold else { return nil }
        guard let sessionId = signal.contextSessionId, !sessionId.isEmpty else { return nil }
        guard !state.contextSeenSessions.contains(sessionId) else { return nil }

        let id = contextId(forSession: sessionId)
        guard !state.mutedIds.contains(id) else { return nil }

        let rounded = Int(pct.rounded())
        return DueNotification(
            kind: .context,
            id: id,
            title: "Context at \(rounded)%",
            body: "Quality can dip past ~\(Int(Self.contextThreshold))%. Start a fresh session, or write a handoff note and /compact."
        )
    }

    private func timingCandidate(timing: TimingInsight, state: NotificationState, today: String) -> DueNotification? {
        guard !state.isTypeMuted(.timing) else { return nil }
        guard !timing.notEnoughData, let prime = timing.primeHour else { return nil }
        guard state.lastShownDay[NotificationKind.timing.rawValue] != today else { return nil }

        let id = "timing.prime"
        guard !state.mutedIds.contains(id) else { return nil }

        let primeText = hourLabel(prime)
        let body: String
        if let peak = timing.peakHours.min() {
            body = "You tend to peak around \(hourLabel(peak)). Prime a fresh window near \(primeText) so it's ready when you are."
        } else {
            body = "Prime a fresh window near \(primeText) so it's ready when you are."
        }
        return DueNotification(kind: .timing, id: id, title: "Your prime time", body: body)
    }

    private func tipCandidate(state: NotificationState, today: String) -> DueNotification? {
        guard !state.isTypeMuted(.tip) else { return nil }
        guard state.lastShownDay[NotificationKind.tip.rawValue] != today else { return nil }
        guard let tip = nextTip(state: state) else { return nil }
        return DueNotification(kind: .tip, id: tip.id, title: tip.title, body: tip.body)
    }

    /// Next tip not yet seen this cycle and not muted; when every selectable tip
    /// has been seen, the cycle restarts from the top.
    private func nextTip(state: NotificationState) -> Tip? {
        if let unseen = tips.first(where: { !state.seenTipIds.contains($0.id) && !state.mutedIds.contains($0.id) }) {
            return unseen
        }
        return tips.first(where: { !state.mutedIds.contains($0.id) })
    }

    // MARK: - Persisting API (disk I/O)

    /// Loads state, evaluates, and — if a notification is due — records it and
    /// persists before returning. This is the one call the UI polls each tick.
    @discardableResult
    public func poll(now: Date, signal: UsageSignal, timing: TimingInsight) -> DueNotification? {
        var state = loadState()
        guard let due = evaluate(now: now, signal: signal, timing: timing, state: state) else { return nil }
        record(due, at: now, into: &state)
        try? saveState(state)
        return due
    }

    public func currentState() -> NotificationState { loadState() }

    public func setMasterEnabled(_ enabled: Bool) {
        mutate { $0.masterEnabled = enabled }
    }

    public func setType(_ kind: NotificationKind, muted: Bool) {
        mutate {
            if muted { $0.mutedTypes.insert(kind.rawValue) }
            else { $0.mutedTypes.remove(kind.rawValue) }
        }
    }

    /// "Don't show again" for one specific notification, by its stable id.
    public func dontShowAgain(id: String) {
        mutate { $0.mutedIds.insert(id) }
    }

    public func setQuietHours(_ quietHours: QuietHours?) {
        mutate { $0.quietHours = quietHours }
    }

    /// Test/uninstall helper: wipe persisted state back to defaults.
    public func resetState() {
        try? saveState(.default)
    }

    // MARK: - Internals

    private func mutate(_ transform: (inout NotificationState) -> Void) {
        var state = loadState()
        transform(&state)
        try? saveState(state)
    }

    private func loadState() -> NotificationState {
        guard let data = try? Data(contentsOf: stateFile), !data.isEmpty else {
            return .default
        }
        return (try? JSONDecoder().decode(NotificationState.self, from: data)) ?? .default
    }

    private func saveState(_ state: NotificationState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try AtomicFile.write(data, to: stateFile)
    }

    private func contextId(forSession sessionId: String) -> String { "context.\(sessionId)" }

    private func sessionId(fromContextId id: String) -> String? {
        let prefix = "context."
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        return String(format: "%02d:00", h)
    }
}

private extension NotificationState {
    func isTypeMuted(_ kind: NotificationKind) -> Bool {
        mutedTypes.contains(kind.rawValue)
    }
}
