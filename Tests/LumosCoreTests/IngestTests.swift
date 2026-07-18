import Testing
import Foundation
@testable import LumosCore

@Suite struct IngestTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func ingestUpsertsNewSessionViaEnvOverride() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Exercises the same LUMOS_CACHE_DIR resolution the CLI uses, proving
        // the env override actually redirects reads/writes into the sandbox.
        let environment = ["LUMOS_CACHE_DIR": tempDir.path]
        let resolvedCacheFile = LumosPaths.cacheFile(environment: environment)

        let payload = """
        {
          "session_id": "sess-abc",
          "model": { "id": "claude-opus-4-8", "display_name": "Opus" },
          "rate_limits": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
          },
          "context_window": { "used_percentage": 38, "context_window_size": 200000 }
        }
        """
        let now = Date(timeIntervalSince1970: 1_738_371_243)

        let entry = try IngestService.ingest(input: Data(payload.utf8), cacheFile: resolvedCacheFile, now: now)

        #expect(entry.model == "Opus")
        #expect(entry.fiveHour?.usedPercentage == 23.5)
        #expect(entry.sevenDay?.resetsAt == 1738857600)
        #expect(entry.contextWindow?.contextWindowSize == 200000)
        #expect(entry.updatedAt == 1_738_371_243)

        let cache = try CacheReader.load(from: resolvedCacheFile)
        #expect(cache["sess-abc"] == entry)
    }

    @Test func ingestGuardsAgainstMissingSessionId() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let payload = """
        { "model": "claude-opus-4-8", "context_window": { "used_percentage": 10 } }
        """

        do {
            _ = try IngestService.ingest(input: Data(payload.utf8), cacheFile: cacheFile)
            Issue.record("expected missingSessionId to be thrown")
        } catch let error as IngestService.IngestError {
            guard case .missingSessionId = error else {
                Issue.record("expected missingSessionId, got \(error)")
                return
            }
        }

        #expect(!FileManager.default.fileExists(atPath: cacheFile.path), "a guarded failure must not create a cache file")
    }

    @Test func ingestGuardsAgainstMalformedJSON() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        do {
            _ = try IngestService.ingest(input: Data("not json".utf8), cacheFile: cacheFile)
            Issue.record("expected invalidJSON to be thrown")
        } catch let error as IngestService.IngestError {
            guard case .invalidJSON = error else {
                Issue.record("expected invalidJSON, got \(error)")
                return
            }
        }
    }

    @Test func ingestGuardsMissingRateLimitsAndNullContextPercentage() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let payload = """
        {
          "session_id": "sess-non-pro",
          "context_window": { "used_percentage": null, "context_window_size": 200000 }
        }
        """
        let entry = try IngestService.ingest(input: Data(payload.utf8), cacheFile: cacheFile, now: Date(timeIntervalSince1970: 1000))
        #expect(entry.fiveHour == nil)
        #expect(entry.sevenDay == nil)
        #expect(entry.contextWindow?.usedPercentage == nil)
        #expect(entry.contextWindow?.contextWindowSize == 200000)
    }

    @Test func ingestUpsertOverwritesSameSession() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let first = """
        { "session_id": "sess-1", "context_window": { "used_percentage": 10 } }
        """
        let second = """
        { "session_id": "sess-1", "context_window": { "used_percentage": 55 } }
        """
        _ = try IngestService.ingest(input: Data(first.utf8), cacheFile: cacheFile, now: Date(timeIntervalSince1970: 1000))
        _ = try IngestService.ingest(input: Data(second.utf8), cacheFile: cacheFile, now: Date(timeIntervalSince1970: 2000))

        let cache = try CacheReader.load(from: cacheFile)
        #expect(cache.count == 1)
        #expect(cache["sess-1"]?.contextWindow?.usedPercentage == 55)
        #expect(cache["sess-1"]?.updatedAt == 2000)
    }

    @Test func ingestWritesAtomicallyLeavingNoTempFile() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let payload = """
        { "session_id": "sess-1", "context_window": { "used_percentage": 10 } }
        """
        _ = try IngestService.ingest(input: Data(payload.utf8), cacheFile: cacheFile)

        #expect(FileManager.default.fileExists(atPath: cacheFile.path))
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path + ".tmp"))
    }

    @Test func ingestPrunesVeryOldSessions() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        var cache: LumosCache = [:]
        cache["ancient"] = SessionCacheEntry(updatedAt: 0)
        try CacheWriter.write(cache, to: cacheFile)

        let payload = """
        { "session_id": "fresh", "context_window": { "used_percentage": 5 } }
        """
        let now = Date(timeIntervalSince1970: 1000)
        _ = try IngestService.ingest(input: Data(payload.utf8), cacheFile: cacheFile, now: now, pruneAge: 500)

        let result = try CacheReader.load(from: cacheFile)
        #expect(result["ancient"] == nil, "sessions older than the prune age must be dropped")
        #expect(result["fresh"] != nil)
    }
}
