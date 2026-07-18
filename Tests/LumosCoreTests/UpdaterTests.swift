import Testing
import Foundation
@testable import LumosCore

private struct FakeReleaseFetcher: ReleaseFetching {
    let tag: String

    func latestReleaseTag() async throws -> String {
        tag
    }
}

private struct FailingReleaseFetcher: ReleaseFetching {
    struct Boom: Error {}
    func latestReleaseTag() async throws -> String {
        throw Boom()
    }
}

@Suite final class UpdaterTests {
    private let sandbox: URL
    private let environment: [String: String]

    init() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        environment = ["LUMOS_CACHE_DIR": sandbox.path]
    }

    deinit {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: - isNewer: core cases

    @Test func newerPatchIsNewer() {
        #expect(UpdateChecker.isNewer("1.2.4", than: "1.2.3"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!UpdateChecker.isNewer("1.2.2", than: "1.2.3"))
    }

    @Test func equalVersionsAreNotNewer() {
        #expect(!UpdateChecker.isNewer("1.2.3", than: "1.2.3"))
    }

    @Test func newerMinorBeatsHigherPatchOnOlderMinor() {
        #expect(UpdateChecker.isNewer("1.3.0", than: "1.2.9"))
    }

    @Test func newerMajorBeatsEverything() {
        #expect(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
    }

    // MARK: - v-prefix

    @Test func vPrefixIsIgnoredOnBothSides() {
        #expect(UpdateChecker.isNewer("v1.2.4", than: "v1.2.3"))
        #expect(UpdateChecker.isNewer("v1.2.4", than: "1.2.3"))
        #expect(!UpdateChecker.isNewer("1.2.3", than: "v1.2.3"))
    }

    // MARK: - Missing patch / minor

    @Test func missingPatchDefaultsToZero() {
        #expect(!UpdateChecker.isNewer("1.2", than: "1.2.0"))
        #expect(UpdateChecker.isNewer("1.3", than: "1.2.9"))
    }

    @Test func missingMinorAndPatchDefaultToZero() {
        #expect(!UpdateChecker.isNewer("2", than: "2.0.0"))
        #expect(UpdateChecker.isNewer("3", than: "2.9.9"))
    }

    // MARK: - Pre-release ordering

    @Test func releaseBeatsItsOwnPrerelease() {
        #expect(UpdateChecker.isNewer("1.2.3", than: "1.2.3-beta.1"))
        #expect(!UpdateChecker.isNewer("1.2.3-beta.1", than: "1.2.3"))
    }

    @Test func laterPrereleaseNumberIsNewer() {
        #expect(UpdateChecker.isNewer("1.2.3-beta.2", than: "1.2.3-beta.1"))
        #expect(!UpdateChecker.isNewer("1.2.3-beta.1", than: "1.2.3-beta.2"))
    }

    @Test func numericPrereleaseIdentifierComparesNumerically() {
        // "beta.11" must beat "beta.2" — not a lexical "11" < "2" string compare.
        #expect(UpdateChecker.isNewer("1.2.3-beta.11", than: "1.2.3-beta.2"))
    }

    @Test func alphanumericPrereleaseOutranksNumericAtSamePosition() {
        #expect(UpdateChecker.isNewer("1.2.3-rc.1", than: "1.2.3-beta.99"))
    }

    @Test func longerPrereleaseWithSharedPrefixIsNewer() {
        #expect(UpdateChecker.isNewer("1.2.3-beta.1.extra", than: "1.2.3-beta.1"))
    }

    @Test func buildMetadataIsIgnoredForPrecedence() {
        #expect(!UpdateChecker.isNewer("1.2.3+build.5", than: "1.2.3+build.9"))
        #expect(UpdateChecker.isNewer("1.2.4+build.1", than: "1.2.3+build.999"))
    }

    // MARK: - status(current:latest:)

    @Test func statusReportsAvailableWhenLatestIsNewer() {
        let status = UpdateChecker.status(current: "1.0.0", latest: "v1.1.0")
        #expect(status == .available(version: "v1.1.0"))
    }

    @Test func statusReportsUpToDateWhenLatestIsSameOrOlder() {
        #expect(UpdateChecker.status(current: "1.1.0", latest: "1.1.0") == .upToDate)
        #expect(UpdateChecker.status(current: "1.1.0", latest: "1.0.0") == .upToDate)
    }

    // MARK: - Throttle: last-checked persistence

    @Test func firstCheckIsAlwaysDue() {
        #expect(UpdateChecker.isCheckDue(now: Date(), environment: environment))
    }

    @Test func checkIsNotDueWithinIntervalAfterRecording() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try UpdateChecker.recordChecked(now: now, environment: environment)

        let stillWithinDay = now.addingTimeInterval(60 * 60 * 23)
        #expect(!UpdateChecker.isCheckDue(now: stillWithinDay, environment: environment))
    }

    @Test func checkIsDueAgainAfterIntervalElapses() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try UpdateChecker.recordChecked(now: now, environment: environment)

        let nextDay = now.addingTimeInterval(60 * 60 * 24 + 1)
        #expect(UpdateChecker.isCheckDue(now: nextDay, environment: environment))
    }

    @Test func checkForUpdateSkipsFetchWhenNotDue() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try UpdateChecker.recordChecked(now: now, environment: environment)

        let result = try await UpdateChecker.checkForUpdate(
            currentVersion: "1.0.0",
            fetcher: FailingReleaseFetcher(),
            now: now.addingTimeInterval(60),
            environment: environment
        )
        #expect(result == nil, "must not touch the network when a check already happened today")
    }

    @Test func checkForUpdateFetchesAndRecordsWhenDue() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let result = try await UpdateChecker.checkForUpdate(
            currentVersion: "1.0.0",
            fetcher: FakeReleaseFetcher(tag: "v1.2.0"),
            now: now,
            environment: environment
        )
        #expect(result == .available(version: "v1.2.0"))

        let recorded = try #require(UpdateChecker.lastCheckedAt(environment: environment))
        #expect(recorded == now)
    }

    @Test func checkForUpdateRecordsEvenOnFetchFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        await #expect(throws: FailingReleaseFetcher.Boom.self) {
            _ = try await UpdateChecker.checkForUpdate(
                currentVersion: "1.0.0",
                fetcher: FailingReleaseFetcher(),
                now: now,
                environment: environment
            )
        }
    }

    // MARK: - Upgrade invocation

    @Test func upgradeCommandNeverExecutesOnlyConstructs() {
        #expect(UpdateChecker.upgradeCommand() == ["brew", "upgrade", "lumos"])
        #expect(UpdateChecker.upgradeCommand(formula: "lumos-beta") == ["brew", "upgrade", "lumos-beta"])
    }
}
