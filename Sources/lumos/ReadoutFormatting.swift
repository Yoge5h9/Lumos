#if canImport(AppKit)
import Foundation
import LumosCore

/// Builds the human-readable strings the Readout/HUD show, from a cache
/// aggregate + its freshness. Two densities: `compact` for the resting notch
/// Readout (`65% · 2h 14m` — a relative countdown), and `full` for the LED HUD
/// (`65% used · resets 6:05 PM IST · wk 41%`). Only `waiting` (no data ever)
/// collapses to "waiting for Claude Code…"; Stale keeps its frozen numbers.
/// Absolute reset time is shown in **IST** for now (DECISIONS.md).
enum ReadoutFormatting {
    static let indiaTimeZone = TimeZone(identifier: "Asia/Kolkata")

    /// The 5-hour window length, used to derive the next reset once Refilled.
    private static let fiveHourWindow: Int64 = 5 * 60 * 60

    struct Fields {
        let primary: String    // "65%" / "65% used" / "waiting for Claude Code…"
        let reset: String?     // "2h 14m" (compact) / "resets 6:05 PM IST" (full)
        let weekly: String?    // "wk 41%" (full only)
        let isIdle: Bool       // waiting → plain, no accent
    }

    /// The used-% and reset instant to display, after freshness is resolved:
    /// Stale/Live show the frozen last-known values (the reset is absolute, so
    /// its countdown legitimately keeps ticking); Refilled derives ~0% used and
    /// the next window boundary from the clock; Waiting shows nothing.
    struct Resolved {
        let usedPercentage: Double?
        let resetEpoch: Int64?
    }

    static func resolved(for aggregate: CacheAggregate, freshness: Freshness) -> Resolved {
        guard let five = aggregate.latestSnapshot?.fiveHour else {
            return Resolved(usedPercentage: nil, resetEpoch: nil)
        }
        switch freshness {
        case .waiting:
            return Resolved(usedPercentage: nil, resetEpoch: nil)
        case .refilled:
            return Resolved(usedPercentage: 0, resetEpoch: five.resetsAt.map { $0 + fiveHourWindow })
        case .live, .stale:
            return Resolved(usedPercentage: five.usedPercentage, resetEpoch: five.resetsAt)
        }
    }

    /// The resting notch Readout: `65% · 2h 14m`. No "used", no absolute time,
    /// no weekly — those live in the HUD / menu.
    static func compact(for aggregate: CacheAggregate, freshness: Freshness, now: Date = Date()) -> Fields {
        guard freshness != .waiting else {
            return Fields(primary: waitingPrimary, reset: nil, weekly: nil, isIdle: true)
        }
        let resolved = resolved(for: aggregate, freshness: freshness)
        let primary = resolved.usedPercentage.map { "\(Int($0.rounded()))%" } ?? "usage unknown"
        let reset = resolved.resetEpoch.map { "\(relativeReset(epoch: $0, now: now)) to reset" }
        return Fields(primary: primary, reset: reset, weekly: nil, isIdle: false)
    }

    /// The full breakdown for the LED HUD: `65% used · resets 6:05 PM IST · wk 41%`.
    static func full(for aggregate: CacheAggregate, freshness: Freshness, now: Date = Date()) -> Fields {
        guard freshness != .waiting else {
            return Fields(primary: waitingPrimary, reset: nil, weekly: nil, isIdle: true)
        }
        let resolved = resolved(for: aggregate, freshness: freshness)
        let primary = resolved.usedPercentage.map { "\(Int($0.rounded()))% used" } ?? "usage unknown"
        let reset = resolved.resetEpoch.map { "resets \(absoluteTime(epoch: $0))" }
        let weekly = aggregate.latestSnapshot?.sevenDay?.usedPercentage
            .map { "wk \(Int($0.rounded()))%" }
        return Fields(primary: primary, reset: reset, weekly: weekly, isIdle: false)
    }

    static let waitingPrimary = "waiting for Claude Code…"

    /// The muted "stale · updated Xm ago" sub-label text, relative to the last
    /// tick. Nil unless actually Stale.
    static func staleSubLabel(for aggregate: CacheAggregate, freshness: Freshness, now: Date = Date()) -> String? {
        guard freshness == .stale, let updatedAt = aggregate.latestSnapshot?.updatedAt else { return nil }
        return "stale · updated \(relativeAge(sinceEpoch: updatedAt, now: now))"
    }

    /// "2h 14m" / "47m" — time until an absolute reset instant.
    static func relativeReset(epoch: Int64, now: Date) -> String {
        let totalMinutes = max(0, Int((Double(epoch) - now.timeIntervalSince1970) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// "6m ago" / "just now" — elapsed time since an absolute instant.
    static func relativeAge(sinceEpoch epoch: Int64, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince1970 - Double(epoch))
        if seconds < 60 { return "just now" }
        return "\(Int(seconds / 60))m ago"
    }

    private static func absoluteTime(epoch: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = indiaTimeZone
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch))) + " IST"
    }
}
#endif
