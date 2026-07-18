import Foundation

/// The shape Claude Code's status-line command receives on stdin. Only the
/// fields Lumos cares about are modeled; everything else on the payload is
/// ignored. `model` is decoded defensively since it has appeared both as a
/// bare string and as an object with a `display_name` — either way Lumos only
/// ever needs a human-readable name out of it.
struct StatusLinePayload: Decodable {
    struct RateLimits: Decodable {
        let fiveHour: RateLimitWindow?
        let sevenDay: RateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct ModelObject: Decodable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    let sessionId: String?
    let rateLimits: RateLimits?
    let contextWindow: ContextWindowInfo?
    let modelName: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case rateLimits = "rate_limits"
        case contextWindow = "context_window"
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        rateLimits = try container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
        contextWindow = try container.decodeIfPresent(ContextWindowInfo.self, forKey: .contextWindow)

        if let modelString = try? container.decode(String.self, forKey: .model) {
            modelName = modelString
        } else if let modelObject = try? container.decode(ModelObject.self, forKey: .model) {
            modelName = modelObject.displayName ?? modelObject.id
        } else {
            modelName = nil
        }
    }
}

/// Implements `lumos ingest`: parse one status-line JSON payload from stdin,
/// upsert its session into the cache, prune stale sessions, write atomically.
/// Kept in `LumosCore` (rather than the executable target) so it can be
/// exercised directly in tests against a sandbox path, with no subprocess.
public enum IngestService {
    public enum IngestError: Error, CustomStringConvertible {
        case invalidJSON(underlying: Error)
        case missingSessionId

        public var description: String {
            switch self {
            case .invalidJSON(let underlying):
                return "status-line payload is not valid JSON: \(underlying)"
            case .missingSessionId:
                return "status-line payload has no session_id — nothing to key the cache entry on"
            }
        }
    }

    /// Runs the full ingest step against `input` (the raw stdin bytes),
    /// writing the updated cache to `cacheFile`. Never partially writes: on
    /// any guard failure, the existing cache file is left untouched.
    @discardableResult
    public static func ingest(
        input: Data,
        cacheFile: URL,
        now: Date = Date(),
        pruneAge: TimeInterval = CacheWriter.defaultPruneAge
    ) throws -> SessionCacheEntry {
        let payload: StatusLinePayload
        do {
            payload = try JSONDecoder().decode(StatusLinePayload.self, from: input)
        } catch {
            throw IngestError.invalidJSON(underlying: error)
        }

        guard let sessionId = payload.sessionId, !sessionId.isEmpty else {
            throw IngestError.missingSessionId
        }

        let entry = SessionCacheEntry(
            fiveHour: payload.rateLimits?.fiveHour,
            sevenDay: payload.rateLimits?.sevenDay,
            contextWindow: payload.contextWindow,
            model: payload.modelName,
            updatedAt: Int64(now.timeIntervalSince1970)
        )

        var cache = CacheReader.loadTolerant(from: cacheFile)
        CacheWriter.upsert(entry, forSession: sessionId, into: &cache)
        CacheWriter.pruneStaleSessions(&cache, olderThan: pruneAge, now: now)
        try CacheWriter.write(cache, to: cacheFile)

        return entry
    }
}
