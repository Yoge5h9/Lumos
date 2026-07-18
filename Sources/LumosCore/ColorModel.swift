import Foundation

/// The shared color/risk vocabulary the UI consumes. Each state maps to one
/// canonical hex — the whole glance signal is the color.
public enum UsageState: String, Equatable, CaseIterable {
    /// Healthy — plenty of runway.
    case calm
    /// Pay attention — getting into the window.
    case watch
    /// Near / at the limit, or burning fast enough to run out before reset.
    case alert
    /// No fresh data / window reset / waiting for Claude Code.
    case idle

    /// Canonical hex, uppercase with leading `#`.
    public var hex: String {
        switch self {
        case .calm: return "#30D158"
        case .watch: return "#FFD60A"
        case .alert: return "#FF453A"
        case .idle: return "#8C8C8C"
        }
    }

    /// The same color as sRGB components in `0...1`. LumosCore stays free of any
    /// UI framework, so this is the NSColor-free representation callers build a
    /// color from.
    public var rgb: (red: Double, green: Double, blue: Double) {
        let hex = self.hex.dropFirst()
        func channel(_ offset: Int) -> Double {
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            let value = UInt8(hex[start..<end], radix: 16) ?? 0
            return Double(value) / 255.0
        }
        return (channel(0), channel(2), channel(4))
    }
}

/// A rolling buffer of `(used%, when)` samples of the 5-hour window, used to
/// derive a burn-rate. A burn-rate is only produced once there is enough signal
/// to trust it — at least ``minimumSamples`` spanning at least ``minimumSpan``.
/// Below that bar there is no rate (`nil`), which is what keeps a freshly-opened
/// window from ever being projected into Alert off a tiny early sample.
public struct BurnRateSampler: Equatable {
    /// A single observation of the 5-hour window's used fraction (`0...1`).
    public struct Sample: Equatable {
        public let usedFraction: Double
        public let timestamp: Date

        public init(usedFraction: Double, timestamp: Date) {
            self.usedFraction = usedFraction
            self.timestamp = timestamp
        }
    }

    /// Burn-rate needs at least this many samples before it is trusted.
    public static let minimumSamples = 3
    /// Burn-rate needs the samples to span at least this long (10 minutes).
    public static let minimumSpan: TimeInterval = 600

    public private(set) var samples: [Sample]

    public init(samples: [Sample] = []) {
        self.samples = samples
    }

    /// Append an observation. Accepts a raw `used_percentage` (`0...100`) as it
    /// arrives from the cache; stores it as a fraction.
    public mutating func record(usedPercentage: Double, at timestamp: Date) {
        samples.append(Sample(usedFraction: usedPercentage / 100.0, timestamp: timestamp))
    }

    /// The burn-rate in used-fraction per second (e.g. `0.001` ≈ 0.1%/s), or
    /// `nil` when there is not yet enough signal (`< minimumSamples` samples, or
    /// a span shorter than `minimumSpan`). A least-squares slope over all samples
    /// so a single noisy reading can't dominate.
    public func burnRatePerSecond(
        minimumSamples: Int = BurnRateSampler.minimumSamples,
        minimumSpan: TimeInterval = BurnRateSampler.minimumSpan
    ) -> Double? {
        guard samples.count >= minimumSamples else { return nil }

        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let base = sorted.first!.timestamp.timeIntervalSince1970
        let span = sorted.last!.timestamp.timeIntervalSince1970 - base
        guard span >= minimumSpan else { return nil }

        let n = Double(sorted.count)
        var sumT = 0.0, sumU = 0.0, sumTT = 0.0, sumTU = 0.0
        for sample in sorted {
            let t = sample.timestamp.timeIntervalSince1970 - base
            let u = sample.usedFraction
            sumT += t
            sumU += u
            sumTT += t * t
            sumTU += t * u
        }

        let denominator = n * sumTT - sumT * sumT
        guard abs(denominator) > .ulpOfOne else { return nil }
        return (n * sumTU - sumT * sumU) / denominator
    }
}

/// Maps the aggregated 5-hour usage into a ``UsageState``.
///
/// The color is the *risk of getting blocked before reset*, not raw depletion:
/// usage × time-left × burn-rate projection. Concretely —
///
/// - Below ``calmWatchThreshold`` used → **Calm**. A fresh window can never be
///   anything else, because burn escalation is gated off entirely below 45%.
/// - `calmWatchThreshold ..< alertThreshold` used → **Watch**, unless the burn
///   projection says the window will run dry before reset, which escalates to
///   **Alert**. That escalation ramps in from 45% (no effect) to 75% (full
///   effect) — real depletion has to exist before burn is allowed to color.
/// - At or above ``alertThreshold`` used → **Alert** (near/at the limit).
/// - When reset is within ``resetImminentWindow``, the color relaxes: Alert
///   caps back to Watch, because a refill is imminent.
/// - Stale data, a missing/`nil` 5-hour figure, or a reset already in the past
///   → **Idle**.
///
/// Driven by the 5-hour window only; the 7-day figure never enters the color.
public enum ColorModel {
    /// Calm→Watch boundary, and the point below which burn cannot escalate.
    public static let calmWatchThreshold = 0.45
    /// The point at which burn escalation reaches full weight.
    public static let gateFullThreshold = 0.75
    /// Raw depletion at/above which the window is Alert on its own.
    public static let alertThreshold = 0.90
    /// Within this long of reset, the color relaxes (refill imminent).
    public static let resetImminentWindow: TimeInterval = 900

    /// The pure core. All inputs are injected — no `Date()`, no I/O.
    ///
    /// - Parameters:
    ///   - usedPercentage: 5-hour used percentage (`0...100`), or `nil` if absent.
    ///   - timeLeftSeconds: seconds until reset. `<= 0` or `nil` reads as
    ///     "no live window" → Idle.
    ///   - burnRatePerSecond: used-fraction/second, or `nil` when there isn't
    ///     enough signal (see ``BurnRateSampler``).
    public static func state(
        usedPercentage: Double?,
        timeLeftSeconds: Double?,
        burnRatePerSecond: Double?
    ) -> UsageState {
        guard
            let usedPercentage,
            let timeLeftSeconds,
            timeLeftSeconds > 0
        else { return .idle }

        let used = usedPercentage / 100.0
        let resetImminent = timeLeftSeconds <= resetImminentWindow

        var result: UsageState
        if used >= alertThreshold {
            result = .alert
        } else if used >= calmWatchThreshold {
            result = .watch
            if let burnRatePerSecond {
                let gate = escalationGate(used)
                let projected = used + gate * burnRatePerSecond * timeLeftSeconds
                if projected >= 1.0 {
                    result = .alert
                }
            }
        } else {
            result = .calm
        }

        if resetImminent, result == .alert {
            result = .watch
        }
        return result
    }

    /// Convenience over a ``CacheAggregate``: stale → Idle, otherwise reads the
    /// latest snapshot's 5-hour window and defers to the pure ``state(usedPercentage:timeLeftSeconds:burnRatePerSecond:)``.
    public static func state(
        aggregate: CacheAggregate,
        now: Date = Date(),
        burnRatePerSecond: Double? = nil
    ) -> UsageState {
        guard !aggregate.isStale, let fiveHour = aggregate.latestSnapshot?.fiveHour else {
            return .idle
        }
        let timeLeft = fiveHour.resetsAt.map { Double($0) - now.timeIntervalSince1970 }
        return state(
            usedPercentage: fiveHour.usedPercentage,
            timeLeftSeconds: timeLeft,
            burnRatePerSecond: burnRatePerSecond
        )
    }

    /// The state the latest snapshot's 5-hour window maps to *ignoring*
    /// staleness — the last-known hue to freeze onto a Stale glow. Unlike
    /// ``state(aggregate:now:burnRatePerSecond:)`` this never collapses to Idle
    /// just because the data is old; it reads the frozen numbers as if live.
    public static func lastKnownState(
        aggregate: CacheAggregate,
        now: Date = Date(),
        burnRatePerSecond: Double? = nil
    ) -> UsageState {
        guard let fiveHour = aggregate.latestSnapshot?.fiveHour else { return .idle }
        let timeLeft = fiveHour.resetsAt.map { Double($0) - now.timeIntervalSince1970 }
        return state(
            usedPercentage: fiveHour.usedPercentage,
            timeLeftSeconds: timeLeft,
            burnRatePerSecond: burnRatePerSecond
        )
    }

    /// The burn-escalation ramp: `0` at or below ``calmWatchThreshold``, rising
    /// linearly to `1` at ``gateFullThreshold`` and above.
    static func escalationGate(_ used: Double) -> Double {
        let span = gateFullThreshold - calmWatchThreshold
        return min(max((used - calmWatchThreshold) / span, 0), 1)
    }
}
