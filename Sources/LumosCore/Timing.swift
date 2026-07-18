import Foundation

/// One line of `~/.claude/history.jsonl`. `timestamp` is epoch MILLISECONDS
/// (distinct from the cache's epoch-seconds fields). Only the fields Lumos
/// needs are modeled — unknown keys are ignored by `Decodable` automatically.
struct HistoryEvent: Decodable {
    let timestamp: Int64
    let project: String?
}

/// Hour-of-day (0-23, local time) prompt-activity histogram and the derived
/// "prime your window" suggestion.
public struct TimingInsight: Equatable {
    /// Prompt counts indexed by local hour of day, 0...23.
    public let hourCounts: [Int]
    /// Hour(s) tied for the most activity. Empty when there isn't enough data.
    public let peakHours: [Int]
    /// Suggested hour to start a fresh 5-hour window: a bit before the peak.
    /// Nil when there isn't enough data to suggest one.
    public let primeHour: Int?
    public let totalPrompts: Int
    /// True when history is too sparse (too few prompts, or too short a
    /// span) to draw a meaningful conclusion — the cold-start state.
    public let notEnoughData: Bool

    static let insufficientData = TimingInsight(
        hourCounts: Array(repeating: 0, count: 24),
        peakHours: [],
        primeHour: nil,
        totalPrompts: 0,
        notEnoughData: true
    )
}

public enum TimingAnalyzer {
    /// Below this many total prompts, an hour-of-day histogram is mostly noise.
    public static let minimumPrompts = 20
    /// Below this span between the earliest and latest prompt, there hasn't
    /// been enough of a routine to observe a "peak hour" yet.
    public static let minimumSpan: TimeInterval = 3 * 24 * 60 * 60
    /// A fresh window is best started this many hours before the observed peak.
    public static let primeLeadHours = 1

    /// Streams `history.jsonl` line-by-line (never loads the whole file into
    /// memory) building an hour-of-day histogram, tolerating malformed or
    /// blank lines. Returns `.insufficientData` if the file is missing or too
    /// sparse to draw a conclusion from.
    public static func analyze(
        historyFile: URL,
        minimumPrompts: Int = minimumPrompts,
        minimumSpan: TimeInterval = minimumSpan,
        calendar: Calendar = .current
    ) -> TimingInsight {
        guard let handle = FileHandle(forReadingAtPath: historyFile.path) else {
            return .insufficientData
        }
        defer { try? handle.close() }

        var hourCounts = Array(repeating: 0, count: 24)
        var total = 0
        var minTimestampMs: Int64?
        var maxTimestampMs: Int64?

        for line in LineReader(handle: handle) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(HistoryEvent.self, from: data) else {
                continue
            }

            let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000)
            let hour = calendar.component(.hour, from: date)
            guard (0...23).contains(hour) else { continue }

            hourCounts[hour] += 1
            total += 1
            minTimestampMs = min(minTimestampMs ?? event.timestamp, event.timestamp)
            maxTimestampMs = max(maxTimestampMs ?? event.timestamp, event.timestamp)
        }

        guard total >= minimumPrompts,
              let minMs = minTimestampMs, let maxMs = maxTimestampMs,
              Double(maxMs - minMs) / 1000 >= minimumSpan else {
            return TimingInsight(
                hourCounts: hourCounts,
                peakHours: [],
                primeHour: nil,
                totalPrompts: total,
                notEnoughData: true
            )
        }

        let peakCount = hourCounts.max() ?? 0
        let peakHours = (0...23).filter { hourCounts[$0] == peakCount && peakCount > 0 }
        let earliestPeak = peakHours.min()
        let primeHour = earliestPeak.map { ($0 - primeLeadHours + 24) % 24 }

        return TimingInsight(
            hourCounts: hourCounts,
            peakHours: peakHours,
            primeHour: primeHour,
            totalPrompts: total,
            notEnoughData: false
        )
    }
}

/// Minimal buffered line iterator over a `FileHandle`, so large history files
/// are never fully materialized in memory just to compute a histogram.
private struct LineReader: Sequence, IteratorProtocol {
    private let handle: FileHandle
    private var buffer = Data()
    private var reachedEOF = false
    private static let chunkSize = 64 * 1024

    init(handle: FileHandle) {
        self.handle = handle
    }

    mutating func next() -> String? {
        while true {
            if let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                let line = String(data: lineData, encoding: .utf8) ?? ""
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                return line
            }

            if reachedEOF {
                if buffer.isEmpty {
                    return nil
                }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                return line
            }

            let chunk = handle.readData(ofLength: Self.chunkSize)
            if chunk.isEmpty {
                reachedEOF = true
            } else {
                buffer.append(chunk)
            }
        }
    }
}
