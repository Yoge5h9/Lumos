#if canImport(AppKit)
import Foundation
import LumosCore

/// Builds the human-readable strings the Readout/HUD show, from a cache
/// aggregate. Reset time is displayed in **IST** for now (DECISIONS.md:
/// "Timezone: IST hardcoded for now"). Stale/idle collapses to a plain
/// "waiting for Claude Code…" line rather than a stale value.
enum ReadoutFormatting {
    static let indiaTimeZone = TimeZone(identifier: "Asia/Kolkata")

    struct Fields {
        let used: String       // "68% used" or "waiting for Claude Code…"
        let reset: String?     // "resets 6:05 PM IST"
        let weekly: String?    // "wk 41%"
        let isIdle: Bool
    }

    static func fields(for aggregate: CacheAggregate) -> Fields {
        guard !aggregate.isStale, let five = aggregate.latestSnapshot?.fiveHour else {
            return Fields(used: "waiting for Claude Code…", reset: nil, weekly: nil, isIdle: true)
        }

        let used = five.usedPercentage.map { "\(Int($0.rounded()))% used" } ?? "usage unknown"
        let reset = five.resetsAt.map { "resets \(timeString(epoch: $0))" }
        let weekly = aggregate.latestSnapshot?.sevenDay?.usedPercentage
            .map { "wk \(Int($0.rounded()))%" }

        return Fields(used: used, reset: reset, weekly: weekly, isIdle: false)
    }

    private static func timeString(epoch: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = indiaTimeZone
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch))) + " IST"
    }
}
#endif
