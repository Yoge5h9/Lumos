import Foundation

/// A `{used_percentage, resets_at}` rate-limit window, shared shape for both
/// the 5-hour and 7-day limits. `resets_at` is an absolute Unix epoch in
/// seconds — always trust it over any "time remaining" derivation, since the
/// reader may not be sampled continuously.
public struct RateLimitWindow: Codable, Equatable {
    public var usedPercentage: Double?
    public var resetsAt: Int64?

    public init(usedPercentage: Double? = nil, resetsAt: Int64? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

/// Context-window utilization for a session. `usedPercentage` is legitimately
/// absent early in a session or immediately after `/compact` — treat nil as
/// "unknown", not zero.
public struct ContextWindowInfo: Codable, Equatable {
    public var usedPercentage: Double?
    public var contextWindowSize: Int?

    public init(usedPercentage: Double? = nil, contextWindowSize: Int? = nil) {
        self.usedPercentage = usedPercentage
        self.contextWindowSize = contextWindowSize
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case contextWindowSize = "context_window_size"
    }
}

/// One session's cached snapshot. Every field beyond `updatedAt` is optional —
/// `rate_limits` is absent entirely for non-Pro/Max plans, and any individual
/// sub-field can be missing depending on what Claude Code emitted that tick.
public struct SessionCacheEntry: Codable, Equatable {
    public var fiveHour: RateLimitWindow?
    public var sevenDay: RateLimitWindow?
    public var contextWindow: ContextWindowInfo?
    public var model: String?
    public var updatedAt: Int64

    public init(
        fiveHour: RateLimitWindow? = nil,
        sevenDay: RateLimitWindow? = nil,
        contextWindow: ContextWindowInfo? = nil,
        model: String? = nil,
        updatedAt: Int64
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.contextWindow = contextWindow
        self.model = model
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case contextWindow = "context_window"
        case model
        case updatedAt = "updated_at"
    }
}

/// The on-disk cache: an object keyed by `session_id`, one entry per live
/// Claude Code session Lumos has seen a status-line tick from.
public typealias LumosCache = [String: SessionCacheEntry]
