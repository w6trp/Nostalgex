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
        let calls = await fixture.result(); XCTAssertEqual(calls.0, 1)
        let marked = await experiment.scrobble(ratingKey: "42"); XCTAssertFalse(marked)
    }
}
