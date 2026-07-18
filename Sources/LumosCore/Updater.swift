import Foundation

/// Result of comparing the running version against the newest published release.
public enum UpdateStatus: Equatable {
    case upToDate
    case available(version: String)
}

/// Abstracts "what is the newest released version" so `UpdateChecker` never
/// hard-codes a network call — tests inject a fake, production wires
/// `GitHubReleaseFetcher`. This is the ONE optional network call Lumos makes,
/// and it must never carry anything beyond the version query itself.
public protocol ReleaseFetching {
    func latestReleaseTag() async throws -> String
}

/// Fetches the newest release tag from the GitHub Releases API
/// (`/repos/<owner>/<repo>/releases/latest`). Sends nothing but the request
/// itself — no identifying data, no telemetry.
public struct GitHubReleaseFetcher: ReleaseFetching {
    public enum FetchError: Error, CustomStringConvertible {
        case invalidResponse
        case httpError(Int)
        case missingTagName

        public var description: String {
            switch self {
            case .invalidResponse:
                return "GitHub releases endpoint returned a non-HTTP response"
            case .httpError(let code):
                return "GitHub releases endpoint returned HTTP \(code)"
            case .missingTagName:
                return "GitHub releases response had no tag_name"
            }
        }
    }

    private let owner: String
    private let repo: String
    private let session: URLSession

    public init(owner: String, repo: String, session: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.session = session
    }

    public func latestReleaseTag() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetchError.httpError(http.statusCode)
        }

        struct ReleasePayload: Decodable {
            let tagName: String
            private enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
            }
        }
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        guard !payload.tagName.isEmpty else {
            throw FetchError.missingTagName
        }
        return payload.tagName
    }
}

/// Semver-ish precedence compare plus the once-a-day throttle bookkeeping.
/// Never executes anything — this only decides *whether* to ask and what the
/// answer was; the caller wires the result to UI and to running the upgrade.
public enum UpdateChecker {
    /// How long a completed check is considered fresh before another is due.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    private static let stateFileName = "updater-state.json"

    private struct PersistedState: Codable {
        let lastCheckedAt: Double
    }

    public static func stateFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        LumosPaths.cacheDir(environment: environment).appendingPathComponent(stateFileName, isDirectory: false)
    }

    /// Nil means "never checked" — always due.
    public static func lastCheckedAt(environment: [String: String] = ProcessInfo.processInfo.environment) -> Date? {
        guard let data = try? Data(contentsOf: stateFile(environment: environment)),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return nil
        }
        return Date(timeIntervalSince1970: state.lastCheckedAt)
    }

    public static func isCheckDue(
        now: Date,
        checkInterval: TimeInterval = checkInterval,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let last = lastCheckedAt(environment: environment) else { return true }
        return now.timeIntervalSince(last) >= checkInterval
    }

    public static func recordChecked(
        now: Date,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let state = PersistedState(lastCheckedAt: now.timeIntervalSince1970)
        try AtomicFile.write(try JSONEncoder().encode(state), to: stateFile(environment: environment))
    }

    /// Pure: given what the fetcher already returned, what should the UI show.
    public static func status(current: String, latest: String) -> UpdateStatus {
        isNewer(latest, than: current) ? .available(version: latest) : .upToDate
    }

    /// Runs the once-a-day-throttled check: skips the network call entirely
    /// (returning nil) when a check already happened within `checkInterval`,
    /// otherwise fetches, records the attempt regardless of outcome so a
    /// flaky network doesn't cause retries every launch, and returns the status.
    public static func checkForUpdate(
        currentVersion: String,
        fetcher: ReleaseFetching,
        now: Date = Date(),
        checkInterval: TimeInterval = checkInterval,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> UpdateStatus? {
        guard isCheckDue(now: now, checkInterval: checkInterval, environment: environment) else {
            return nil
        }
        do {
            let latestTag = try await fetcher.latestReleaseTag()
            try recordChecked(now: now, environment: environment)
            return status(current: currentVersion, latest: latestTag)
        } catch {
            try? recordChecked(now: now, environment: environment)
            throw error
        }
    }

    /// The command the UI runs (via `Process`) when the user clicks
    /// "Update available" — constructed here, never executed here.
    public static func upgradeCommand(formula: String = "lumos") -> [String] {
        ["brew", "upgrade", formula]
    }

    // MARK: - Version compare

    /// True when `candidate` has higher precedence than `current`. Accepts
    /// `vX.Y.Z` or bare `X.Y.Z`, tolerates a missing patch (and even minor)
    /// component by treating it as zero, strips build metadata (`+...`), and
    /// compares pre-release identifiers per semver precedence rules (a
    /// release beats any of its pre-releases; shared identifiers compare
    /// numerically when both sides parse as integers, lexically otherwise).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let c = SemanticVersion(parsing: candidate)
        let r = SemanticVersion(parsing: current)

        if c.core != r.core {
            return isCoreGreater(c.core, r.core)
        }
        if c.prerelease.isEmpty != r.prerelease.isEmpty {
            // Whichever side has no pre-release identifiers is the full release.
            return c.prerelease.isEmpty
        }
        if c.prerelease.isEmpty && r.prerelease.isEmpty {
            return false
        }
        return isPrereleaseGreater(c.prerelease, r.prerelease)
    }

    private static func isCoreGreater(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            return x > y
        }
        return false
    }

    private static func isPrereleaseGreater(_ a: [String], _ b: [String]) -> Bool {
        let count = max(a.count, b.count)
        for i in 0..<count {
            guard i < a.count else { return false } // a ran out of identifiers first: lower precedence
            guard i < b.count else { return true }  // b ran out first: a is greater
            let x = a[i], y = b[i]
            if x == y { continue }
            switch (Int(x), Int(y)) {
            case let (xn?, yn?):
                return xn > yn
            case (nil, nil):
                return x > y
            case (_?, nil):
                return false // numeric identifiers always have lower precedence than alphanumeric ones
            case (nil, _?):
                return true
            }
        }
        return false
    }

    private struct SemanticVersion {
        let core: [Int]
        let prerelease: [String]

        init(parsing raw: String) {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("v") || s.hasPrefix("V") {
                s.removeFirst()
            }
            if let plusIndex = s.firstIndex(of: "+") {
                s = String(s[s.startIndex..<plusIndex])
            }

            let corePart: Substring
            let prereleasePart: Substring?
            if let dashIndex = s.firstIndex(of: "-") {
                corePart = s[s.startIndex..<dashIndex]
                prereleasePart = s[s.index(after: dashIndex)...]
            } else {
                corePart = s[s.startIndex...]
                prereleasePart = nil
            }

            var numbers = corePart.split(separator: ".").map { Int($0) ?? 0 }
            while numbers.count < 3 { numbers.append(0) }
            core = Array(numbers.prefix(3))
            prerelease = prereleasePart?.split(separator: ".").map(String.init) ?? []
        }
    }
}
