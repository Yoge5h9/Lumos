import Testing
import Foundation
@testable import LumosCore

@Suite struct TimingTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func tempHistoryFile() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl")
    }

    private func line(hour: Int, dayOffset: Int, calendar: Calendar) -> String {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1 + dayOffset
        components.hour = hour
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components)!
        let ms = Int64(date.timeIntervalSince1970 * 1000)
        return "{\"timestamp\": \(ms), \"project\": \"demo\"}"
    }

    @Test func missingFileReturnsInsufficientData() {
        let url = tempHistoryFile() // never written
        let insight = TimingAnalyzer.analyze(historyFile: url)
        #expect(insight.notEnoughData)
        #expect(insight.totalPrompts == 0)
        #expect(insight.primeHour == nil)
    }

    @Test func coldStartTooFewPrompts() throws {
        let url = tempHistoryFile()
        let calendar = utcCalendar
        let lines = (0..<5).map { line(hour: 11, dayOffset: $0, calendar: calendar) }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let insight = TimingAnalyzer.analyze(historyFile: url, calendar: calendar)
        #expect(insight.notEnoughData)
    }

    @Test func coldStartTooShortSpan() throws {
        let url = tempHistoryFile()
        let calendar = utcCalendar
        let lines = (0..<25).map { _ in line(hour: 11, dayOffset: 0, calendar: calendar) }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let insight = TimingAnalyzer.analyze(historyFile: url, calendar: calendar)
        #expect(insight.notEnoughData, "25 prompts all in one sitting is not enough span, regardless of count")
    }

    @Test func computesPeakHourAndPrimeSuggestion() throws {
        let url = tempHistoryFile()
        let calendar = utcCalendar
        var lines: [String] = []
        for day in 0..<5 {
            for _ in 0..<6 {
                lines.append(line(hour: 11, dayOffset: day, calendar: calendar))
            }
            lines.append(line(hour: 9, dayOffset: day, calendar: calendar))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let insight = TimingAnalyzer.analyze(historyFile: url, calendar: calendar)
        #expect(insight.notEnoughData == false)
        #expect(insight.peakHours == [11])
        #expect(insight.primeHour == 10, "prime suggestion is a bit before the peak")
        #expect(insight.totalPrompts == 35)
        #expect(insight.hourCounts[11] == 30)
        #expect(insight.hourCounts[9] == 5)
    }

    @Test func tolerantOfMalformedAndBlankLines() throws {
        let url = tempHistoryFile()
        let calendar = utcCalendar
        var lines: [String] = []
        for day in 0..<5 {
            for _ in 0..<6 {
                lines.append(line(hour: 14, dayOffset: day, calendar: calendar))
            }
        }
        lines.insert("", at: 3)
        lines.insert("not json at all", at: 7)
        lines.insert("{\"project\": \"missing-timestamp\"}", at: 10)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let insight = TimingAnalyzer.analyze(historyFile: url, calendar: calendar)
        #expect(insight.notEnoughData == false)
        #expect(insight.totalPrompts == 30, "malformed/blank lines must be skipped, not counted or crash")
        #expect(insight.peakHours == [14])
    }
}
