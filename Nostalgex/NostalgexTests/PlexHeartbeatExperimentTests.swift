import XCTest
@testable import Nostalgex

private actor HeartbeatFixture: PlexPlaybackReporting {
    var writes = 0
    var watched = 0
    var sentPositions: [Int?] = []
    let mutate: Bool
    let unavailable: Bool
    init(mutate: Bool = false, unavailable: Bool = false) { self.mutate = mutate; self.unavailable = unavailable }
    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int?, durationMs: Int?, sessionID: String) async -> Bool {
        writes += 1; sentPositions += [timeMs, durationMs]; return true
    }
    func scrobble(ratingKey: String) async -> Bool { watched += 1; return true }
    func read(_ path: String) throws -> [String: Any] {
        if unavailable { throw PlexHeartbeatExperiment.Failure.unavailable }
        if path.hasPrefix("/library/metadata/") {
            return ["Metadata": [["ratingKey": "42", "viewCount": 0, "viewOffset": mutate && writes > 0 ? 9000 : 0]]]
        }
        return ["Metadata": [], "totalSize": 0]
    }
    func result() -> (Int, Int, [Int?]) { (writes, watched, sentPositions) }
}

@MainActor
final class PlexHeartbeatExperimentTests: XCTestCase {
    private final class Notice { var value: String? }
    func testAuditStorageFailurePreventsHeartbeat() async {
        let fixture = HeartbeatFixture(); let notice = Notice()
        let experiment = PlexHeartbeatExperiment(api: .init(serverURL: "https://synthetic.invalid", token: "test"),
            sender: fixture, read: { path, _ in try await fixture.read(path) },
            auditWriter: { _ in throw PlexHeartbeatExperiment.Failure.auditUnavailable },
            onStop: { notice.value = $0 })
        let accepted = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "playing",
                                                        timeMs: nil, durationMs: nil, sessionID: "test")
        XCTAssertFalse(accepted)
        let calls = await fixture.result(); XCTAssertEqual(calls.0, 0)
        XCTAssertTrue(notice.value?.contains("audit could not be saved") == true)
    }
    func testAuditIsRetrievableFromTVOSCache() throws {
        let payload = Data("[]".utf8)
        try PlexHeartbeatExperiment.writeAudit(payload)
        let cache = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent("couchwave-heartbeat-audit.json")), payload)
    }
    func testPersistentMutationStopsExperimentAndRefusesNextWrite() async {
        let fixture = HeartbeatFixture(mutate: true); let notice = Notice()
        let experiment = PlexHeartbeatExperiment(api: .init(serverURL: "https://synthetic.invalid", token: "test"),
            sender: fixture, read: { path, _ in try await fixture.read(path) }, onStop: { notice.value = $0 })
        let first = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "playing",
                                                     timeMs: 9999, durationMs: 99999, sessionID: "test")
        let second = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "playing",
                                                      timeMs: nil, durationMs: nil, sessionID: "test")
        let result = await fixture.result()
        XCTAssertFalse(first); XCTAssertFalse(second)
        XCTAssertEqual(result.0, 1); XCTAssertEqual(result.1, 0)
        XCTAssertTrue(result.2.allSatisfy { $0 == nil })
        XCTAssertTrue(notice.value?.contains("watch state or history changed") == true)
    }
    func testUnavailableBaselinePreventsAnyWrite() async {
        let fixture = HeartbeatFixture(unavailable: true); let notice = Notice()
        let experiment = PlexHeartbeatExperiment(api: .init(serverURL: "https://synthetic.invalid", token: "test"),
            sender: fixture, read: { path, _ in try await fixture.read(path) }, onStop: { notice.value = $0 })
        let result = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "playing",
                                                      timeMs: nil, durationMs: nil, sessionID: "test")
        XCTAssertFalse(result)
        let calls = await fixture.result(); XCTAssertEqual(calls.0, 0)
        XCTAssertNotNil(notice.value)
    }
    func testUnchangedStateAllowsHeartbeatUntilExplicitCancellation() async {
        let fixture = HeartbeatFixture(); let notice = Notice()
        let experiment = PlexHeartbeatExperiment(api: .init(serverURL: "https://synthetic.invalid", token: "test"),
            sender: fixture, read: { path, _ in try await fixture.read(path) }, onStop: { notice.value = $0 })
        let accepted = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "paused",
                                                        timeMs: nil, durationMs: nil, sessionID: "test")
        await experiment.cancel()
        let refused = await experiment.reportTimeline(ratingKey: "42", key: "/library/metadata/42", state: "playing",
                                                       timeMs: nil, durationMs: nil, sessionID: "test")
        XCTAssertTrue(accepted); XCTAssertFalse(refused); XCTAssertNil(notice.value)
        let calls = await fixture.result(); XCTAssertEqual(calls.0, 2)
        let marked = await experiment.scrobble(ratingKey: "42"); XCTAssertFalse(marked)
    }
}

private final class HeartbeatTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: elapsed) }
    func advance(_ seconds: TimeInterval) { lock.lock(); elapsed += seconds; lock.unlock() }
}

private actor CleanupFixture: PlexPlaybackReporting {
    struct Report: Equatable { let item: String; let key: String; let state: String; let session: String; let time: Int?; let duration: Int? }
    var reports: [Report] = []
    var watched = 0
    var readsFail = false
    var changed = false
    var gate: CheckedContinuation<Void, Never>?
    var holdFirst = false
    var firstStarted = false
    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int?, durationMs: Int?, sessionID: String) async -> Bool {
        firstStarted = true
        if holdFirst { holdFirst = false; await withCheckedContinuation { gate = $0 } }
        reports.append(Report(item: ratingKey, key: key, state: state, session: sessionID, time: timeMs, duration: durationMs))
        return true
    }
    func scrobble(ratingKey: String) async -> Bool { watched += 1; return true }
    func read(_ path: String) throws -> [String: Any] {
        if readsFail { throw PlexHeartbeatExperiment.Failure.unavailable }
        if path.hasPrefix("/library/metadata/") {
            return ["Metadata": [["ratingKey": String(path.split(separator: "/").last!), "viewOffset": changed ? 99 : 0]]]
        }
        return ["Metadata": [], "totalSize": 0]
    }
    func snapshot() -> [Report] { reports }
    func breakReads() { readsFail = true }
    func mutate() { changed = true }
    func hold() { holdFirst = true }
    func waitForRequest() async { while !firstStarted { await Task.yield() } }
    func release() { gate?.resume(); gate = nil }
}

@MainActor
final class PlexHeartbeatCleanupTests: XCTestCase {
    private final class Notice { var text: String? }
    private func experiment(_ fixture: CleanupFixture, clock: HeartbeatTestClock = .init(), notice: Notice = .init(), predecessor: Task<Void, Never>? = nil) -> PlexHeartbeatExperiment {
        PlexHeartbeatExperiment(api: .init(serverURL: "https://synthetic.invalid", token: "test"), sender: fixture,
            read: { path, _ in try await fixture.read(path) }, auditWriter: { _ in }, clock: { clock.now() },
            automaticallyObserves: false, predecessor: predecessor, onStop: { notice.text = $0 })
    }
    @discardableResult
    private func report(_ experiment: PlexHeartbeatExperiment, item: String = "42", session: String = "exact-session", state: String = "playing") async -> Bool {
        await experiment.reportTimeline(ratingKey: item, key: "/library/metadata/\(item)", state: state,
                                        timeMs: 100, durationMs: 200, sessionID: session)
    }
    func testTimerExpiryClosesExactSessionWithoutPositionOrWatchedWrite() async {
        let fixture = CleanupFixture(); let clock = HeartbeatTestClock(); let notice = Notice()
        let experiment = experiment(fixture, clock: clock, notice: notice)
        await report(experiment)
        clock.advance(600); await experiment.observeNow()
        let accepted = await report(experiment)
        let rows = await fixture.snapshot()
        XCTAssertFalse(accepted); XCTAssertEqual(rows.map(\.state), ["playing", "stopped"])
        XCTAssertTrue(rows.allSatisfy { $0.item == "42" && $0.key == "/library/metadata/42" && $0.session == "exact-session" && $0.time == nil && $0.duration == nil })
        let watched = await fixture.watched; XCTAssertEqual(watched, 0)
        XCTAssertTrue(notice.text?.contains("10 minutes") == true)
    }
    func testRequestAtCutoffClosesPreviousSessionWithoutStartingNextChannel() async {
        let fixture = CleanupFixture(); let clock = HeartbeatTestClock(); let experiment = experiment(fixture, clock: clock)
        await report(experiment); clock.advance(600)
        let accepted = await report(experiment, item: "43", session: "new-session")
        XCTAssertFalse(accepted)
        let rows = await fixture.snapshot()
        XCTAssertEqual(rows.map(\.item), ["42", "42"]); XCTAssertEqual(rows.map(\.state), ["playing", "stopped"])
    }
    func testDisableClosesOnlyCurrentChannelAndNeverRepeatsStop() async {
        let fixture = CleanupFixture(); let experiment = experiment(fixture)
        await report(experiment); await report(experiment, state: "stopped")
        await report(experiment, item: "43", session: "second")
        await experiment.cancel(); await experiment.cancel(); await experiment.observeNow()
        let accepted = await report(experiment)
        let rows = await fixture.snapshot()
        XCTAssertFalse(accepted)
        XCTAssertEqual(rows.map(\.state), ["playing", "stopped", "playing", "stopped"])
        XCTAssertEqual(rows.map(\.session), ["exact-session", "exact-session", "second", "second"])
    }
    func testBackgroundStopThenDisableDoesNotDuplicateCleanup() async {
        let fixture = CleanupFixture(); let experiment = experiment(fixture)
        await report(experiment); await report(experiment, state: "stopped")
        await experiment.cancel()
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing", "stopped"])
    }
    func testBackgroundAndForegroundThenExpiryClosesResumedSession() async {
        let fixture = CleanupFixture(); let clock = HeartbeatTestClock(); let experiment = experiment(fixture, clock: clock)
        await report(experiment); await report(experiment, state: "stopped")
        clock.advance(590); await report(experiment)
        clock.advance(10); await experiment.observeNow()
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing", "stopped", "playing", "stopped"])
        XCTAssertTrue(rows.allSatisfy { $0.session == "exact-session" && $0.time == nil && $0.duration == nil })
    }
    func testDisableBeforeAnyReportDoesNotInventSession() async {
        let fixture = CleanupFixture(); let experiment = experiment(fixture)
        await experiment.cancel(); await report(experiment)
        let rows = await fixture.snapshot(); XCTAssertTrue(rows.isEmpty)
    }
    func testDisableWaitsForInFlightAcknowledgementThenClosesIt() async {
        let fixture = CleanupFixture(); await fixture.hold()
        let experiment = experiment(fixture)
        let inFlight = Task { await self.report(experiment) }
        await fixture.waitForRequest()
        let disable = Task { await experiment.cancel() }
        for _ in 0..<20 { await Task.yield() }
        await fixture.release(); _ = await inFlight.value; await disable.value
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing", "stopped"])
    }
    func testFailedVerificationRefusesCleanupWrite() async {
        let fixture = CleanupFixture(); let experiment = experiment(fixture)
        await report(experiment); await fixture.breakReads(); await experiment.cancel()
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing"])
    }
    func testChangedStateRefusesExpiryCleanupWrite() async {
        let fixture = CleanupFixture(); let clock = HeartbeatTestClock(); let notice = Notice()
        let experiment = experiment(fixture, clock: clock, notice: notice)
        await report(experiment); await fixture.mutate(); clock.advance(600); await experiment.observeNow()
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing"])
        XCTAssertTrue(notice.text?.contains("watch state or history changed") == true)
    }
    func testReactivationWaitsForPreviousCleanupBeforeReusingSessionID() async {
        let fixture = CleanupFixture(); await fixture.hold()
        let first = experiment(fixture)
        let sending = Task { await self.report(first) }; await fixture.waitForRequest()
        let cleanup = Task { await first.cancel() }
        let next = experiment(fixture, predecessor: cleanup)
        let resuming = Task { await self.report(next) }
        await fixture.release(); _ = await sending.value; _ = await resuming.value
        await next.cancel()
        let rows = await fixture.snapshot(); XCTAssertEqual(rows.map(\.state), ["playing", "stopped", "playing", "stopped"])
    }
}
