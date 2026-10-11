import XCTest
@testable import Nostalgex

private actor RecordingPlexReporting: PlexPlaybackReporting {
    private var states: [String] = []
    private var positions: [Int?] = []
    private var durations: [Int?] = []
    private var markResults: [Bool]
    private var markCount = 0
    private var holdFirst: Bool
    private var firstStarted = false
    private var release: CheckedContinuation<Void, Never>?

    init(markResults: [Bool] = [true], holdFirst: Bool = false) {
        self.markResults = markResults
        self.holdFirst = holdFirst
    }
    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int?,
                        durationMs: Int?, sessionID: String) async -> Bool {
        if !firstStarted {
            firstStarted = true
            if holdFirst { await withCheckedContinuation { release = $0 } }
        }
        states.append(state)
        positions.append(timeMs)
        durations.append(durationMs)
        return true
    }
    func scrobble(ratingKey: String) async -> Bool {
        markCount += 1
        return markResults.isEmpty ? true : markResults.removeFirst()
    }
    func waitUntilFirstRequest() async {
        while !firstStarted { await Task.yield() }
    }
    func releaseFirstRequest() { release?.resume(); release = nil }
    func snapshot() -> (states: [String], positions: [Int?], marks: Int) { (states, positions, markCount) }
    func allDurations() -> [Int?] { durations }
}

private actor RecordingWatchReporting: WatchActivityReporting {
    private var events: [MediaServerPlaybackReport.Event] = []
    private var paused: [Bool] = []
    private var results: [Bool]
    private var marks: [Bool]
    init(results: [Bool] = [true], marks: [Bool] = [true]) { self.results = results; self.marks = marks }
    func reportWatchActivity(itemId: String, mediaSourceId: String, playSessionId: String,
                             positionTicks: Int, event: MediaServerPlaybackReport.Event, isPaused: Bool) async -> Bool {
        events.append(event); paused.append(isPaused)
        return results.isEmpty ? true : results.removeFirst()
    }
    func markWatched(itemId: String) async -> Bool { marks.isEmpty ? true : marks.removeFirst() }
    func snapshot() -> (events: [MediaServerPlaybackReport.Event], paused: [Bool]) { (events, paused) }
}

@MainActor
final class PlaybackTrackerTests: XCTestCase {
    private final class Clock { var now: TimeInterval = 0 }
    private func item() -> PlexMediaItem {
        PlexMediaItem(id: "1", title: "Test", artist: nil, episodeTitle: nil, seTag: nil,
                      summary: "", year: 2020, originallyAvailableAt: nil, contentRating: nil,
                      duration: 1, ratingKey: "1", partKey: "/library/parts/1/file.mp4",
                      container: "mp4", videoCodec: "h264", audioCodec: "aac", videoProfile: nil,
                      bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
                      thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil,
                      tmdbID: nil, imdbID: nil, librarySource: .movie)
    }
    private func tracker(_ api: (any PlexPlaybackReporting)?, _ clock: Clock) -> PlaybackTracker {
        PlaybackTracker(item: item(), seekOffset: 0, plexAPI: api, clock: { clock.now },
                        automaticallySchedulesTimer: false)
    }

    func testHeartbeatOmitsPositionDurationAndNeverScrobblesAcrossCompletion() async throws {
        let api = RecordingPlexReporting(); let clock = Clock()
        let t = PlaybackTracker(item: item(), seekOffset: 0, plexAPI: api,
                                reportingMode: .heartbeatOnly, clock: { clock.now }, automaticallySchedulesTimer: false)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        for second in 1...60 {
            clock.now = Double(second)
            t.onPlaybackUpdate(positionSeconds: Double(second), state: .playing)
            if second % 10 == 0 { t.onTimelineTick() }
        }
        t.onPlaybackUpdate(positionSeconds: 60, state: .paused)
        t.stop(); await t.waitForPendingReports()
        let reports = await api.snapshot(); let durations = await api.allDurations()
        XCTAssertEqual(reports.states.first, "playing")
        XCTAssertEqual(reports.states.suffix(2), ["paused", "stopped"])
        XCTAssertTrue(reports.positions.allSatisfy { $0 == nil })
        XCTAssertTrue(durations.allSatisfy { $0 == nil })
        XCTAssertEqual(reports.marks, 0)
        XCTAssertFalse(t.scrobbled)
    }

    func testSwitchingToHeartbeatDropsPositionAndDisablingCancelsFutureReports() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 10, state: .playing)
        await t.waitForPendingReports()
        t.setReporters(plexAPI: api, reportingMode: .heartbeatOnly)
        await t.waitForPendingReports()
        let reports = await api.snapshot()
        XCTAssertEqual(reports.positions, [10_000, nil])
        t.setReporters(plexAPI: nil); t.onTimelineTick(); t.stop()
        await t.waitForPendingReports()
        let after = await api.snapshot()
        XCTAssertEqual(after.states.count, reports.states.count)
        XCTAssertEqual(after.marks, 0)
    }

    func testActualHeartbeatRequestOmitsFieldsRatherThanSendingZero() throws {
        let api = PlexAPIService(serverURL: "https://synthetic.invalid", token: "synthetic-test-token")
        let components = try XCTUnwrap(api.timelineComponents(ratingKey: "42", key: "/library/metadata/42",
            state: "playing", timeMs: nil, durationMs: nil))
        let request = try XCTUnwrap(api.playbackReportRequest(components: components, method: "POST", sessionID: "test-session"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/:/timeline")
        XCTAssertEqual(Set(components.queryItems!.map(\.name)), ["ratingKey", "key", "state"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier"), "test-session")
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-test-token"))
        let full = try XCTUnwrap(api.timelineComponents(ratingKey: "42", key: "/library/metadata/42",
            state: "playing", timeMs: 12_345, durationMs: 60_000))
        XCTAssertEqual(full.queryItems?.first { $0.name == "time" }?.value, "12345")
        XCTAssertEqual(full.queryItems?.first { $0.name == "duration" }?.value, "60000")
    }

    func testReadyAndPreparingDoNotClaimPlaybackOrReportUnseekedPosition() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackUpdate(positionSeconds: 0, state: .paused)
        t.onPlaybackReady(); t.onTimelineTick()
        await t.waitForPendingReports()
        let before = await api.snapshot()
        XCTAssertTrue(before.states.isEmpty)
        t.onPlaybackUpdate(positionSeconds: 12, state: .playing)
        t.onPlaybackPreparing()
        t.onPlaybackUpdate(positionSeconds: 0, state: .paused)
        await t.waitForPendingReports()
        let after = await api.snapshot()
        XCTAssertEqual(after.states, ["playing", "buffering"])
        XCTAssertEqual(after.positions, [12_000, 12_000])
    }

    func testFrozenPlayheadAndBufferingNeverAccumulateWatchTime() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 10; t.onPlaybackUpdate(positionSeconds: 10, state: .playing)
        clock.now = 40; t.onPlaybackUpdate(positionSeconds: 10, state: .buffering)
        clock.now = 60; t.onTimelineTick()
        await t.waitForPendingReports()
        XCTAssertEqual(t.flushWatchSecondsForAnalytics(), 10, accuracy: 0.001)
        XCTAssertFalse(t.scrobbled)
        let reports = await api.snapshot()
        XCTAssertEqual(reports.states.last, "buffering")
        XCTAssertEqual(reports.positions.last ?? nil, 10_000)
        XCTAssertEqual(reports.marks, 0)
    }

    func testPauseAndResumeUseActualSourcePosition() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 5; t.onPlaybackUpdate(positionSeconds: 5, state: .paused)
        clock.now = 100; t.onPlaybackUpdate(positionSeconds: 5, state: .playing)
        clock.now = 105; t.onPlaybackUpdate(positionSeconds: 10, state: .playing)
        t.stop(); await t.waitForPendingReports()
        XCTAssertEqual(t.flushWatchSecondsForAnalytics(), 10, accuracy: 0.001)
        let reports = await api.snapshot()
        XCTAssertEqual(reports.states, ["playing", "paused", "playing", "stopped"])
        XCTAssertEqual(reports.positions.last ?? nil, 10_000)
    }

    func testStopCannotOvertakeDelayedPlayingAndNoPulseFollowsStop() async {
        let api = RecordingPlexReporting(holdFirst: true); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        await api.waitUntilFirstRequest()
        t.stop(); t.onTimelineTick()
        let blocked = await api.snapshot()
        XCTAssertTrue(blocked.states.isEmpty)
        await api.releaseFirstRequest(); await t.waitForPendingReports()
        let reports = await api.snapshot()
        XCTAssertEqual(reports.states, ["playing", "stopped"])
    }

    func testFailedScrobbleDoesNotLatchAndRetryIsBounded() async {
        let api = RecordingPlexReporting(markResults: [false, true]); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 45; t.onPlaybackUpdate(positionSeconds: 45, state: .playing)
        await t.waitForPendingReports()
        XCTAssertFalse(t.scrobbled)
        clock.now = 46; t.onTimelineTick(); await t.waitForPendingReports()
        let early = await api.snapshot(); XCTAssertEqual(early.marks, 1)
        clock.now = 55; t.onTimelineTick(); await t.waitForPendingReports()
        XCTAssertTrue(t.scrobbled)
        let retried = await api.snapshot(); XCTAssertEqual(retried.marks, 2)
    }

    func testBackgroundTimeIsNotWatchedAndForegroundWaitsForPlayer() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(api, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 5; t.onPlaybackUpdate(positionSeconds: 5, state: .playing)
        t.onBackground(); clock.now = 105; t.onForeground(); t.onTimelineTick()
        await t.waitForPendingReports()
        let reports = await api.snapshot(); XCTAssertEqual(reports.states, ["playing", "stopped"])
        XCTAssertEqual(t.flushWatchSecondsForAnalytics(), 5, accuracy: 0.001)
    }

    func testOptInAppliesNowAndOptOutKeepsAnalyticsWithoutMoreWrites() async {
        let api = RecordingPlexReporting(); let clock = Clock(); let t = tracker(nil, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 5; t.onPlaybackUpdate(positionSeconds: 5, state: .playing)
        t.setReporters(plexAPI: api); await t.waitForPendingReports()
        t.setReporters(plexAPI: nil)
        clock.now = 10; t.onPlaybackUpdate(positionSeconds: 10, state: .playing)
        t.onTimelineTick(); t.stop(); await t.waitForPendingReports()
        let reports = await api.snapshot()
        XCTAssertEqual(reports.states, ["playing"])
        XCTAssertEqual(reports.positions, [5_000])
        XCTAssertEqual(t.flushWatchSecondsForAnalytics(), 10, accuracy: 0.001)
    }

    func testNoReporterNeverLatchesWatchedEvenAboveThreshold() async {
        let clock = Clock(); let t = tracker(nil, clock)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 50; t.onPlaybackUpdate(positionSeconds: 50, state: .playing)
        t.stop(); await t.waitForPendingReports()
        XCTAssertFalse(t.scrobbled)
    }
    func testOtherServersReceivePauseAndRetryUnacknowledgedStart() async {
        let reporter = RecordingWatchReporting(results: [false, true, true, true])
        let clock = Clock()
        let t = PlaybackTracker(item: item(), seekOffset: 0, plexAPI: nil, watchReporter: reporter,
                                clock: {clock.now}, automaticallySchedulesTimer: false)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        t.onTimelineTick(); await t.waitForPendingReports()
        clock.now = 5; t.onPlaybackUpdate(positionSeconds: 5, state: .paused)
        t.stop(); await t.waitForPendingReports()
        let reports = await reporter.snapshot()
        XCTAssertEqual(reports.events, [.started, .started, .progress, .stopped])
        XCTAssertEqual(reports.paused, [false, false, true, false])
    }

    func testOtherServersDoNotLatchFailedWatchedMark() async {
        let reporter = RecordingWatchReporting(marks: [false, true]); let clock = Clock()
        let t = PlaybackTracker(item: item(), seekOffset: 0, plexAPI: nil, watchReporter: reporter,
                                clock: {clock.now}, automaticallySchedulesTimer: false)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing)
        clock.now = 45; t.onPlaybackUpdate(positionSeconds: 45, state: .playing)
        await t.waitForPendingReports(); XCTAssertFalse(t.scrobbled)
        clock.now = 55; t.onTimelineTick(); await t.waitForPendingReports()
        XCTAssertTrue(t.scrobbled)
    }

    func testOtherServersRequestBodyPreservesPauseAndSourcePosition() async {
        let request = MediaServerPlaybackReport.request(serverURL: "https://example.invalid", authorization: "test",
            event: .progress, itemId: "item", mediaSourceId: "source", playSessionId: "session",
            positionTicks: 12_000_000, isPaused: true)!
        let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["IsPaused"] as? Bool, true)
        XCTAssertEqual(body["PositionTicks"] as? Int, 12_000_000)
        XCTAssertEqual(body["PlaySessionId"] as? String, "session")
        XCTAssertEqual(request.url?.path, "/Sessions/Playing/Progress")
    }

    func testMultipartUsesOneSessionAndWholeMovieThreshold() async {
        var movie = item()
        movie.additionalPartKeys = ["/library/parts/2/file.mp4"]
        movie.exactDurationSeconds = 60
        let api = RecordingPlexReporting(); let clock = Clock()
        let t = PlaybackTracker(item: movie, seekOffset: 0, plexAPI: api, clock: {clock.now},
                                automaticallySchedulesTimer: false)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing, durationSeconds: 30)
        clock.now = 30; t.onPlaybackUpdate(positionSeconds: 30, state: .playing, durationSeconds: 30)
        await t.waitForPendingReports()
        let first = await api.snapshot(); XCTAssertEqual(first.marks, 0)
        t.onPlaybackPreparing(); t.onPlaybackReady()
        t.onPlaybackUpdate(positionSeconds: 30, state: .playing, durationSeconds: 30)
        clock.now = 45
        t.onPlaybackUpdate(positionSeconds: 45, state: .playing, durationSeconds: 60, durationIsWholeItem: true)
        await t.waitForPendingReports()
        XCTAssertTrue(t.scrobbled)
        clock.now = 60
        t.onPlaybackUpdate(positionSeconds: 60, state: .playing, durationSeconds: 60, durationIsWholeItem: true)
        t.stop(); await t.waitForPendingReports()
        let reports = await api.snapshot()
        XCTAssertEqual(reports.marks, 1)
        XCTAssertEqual(reports.states.filter { $0 == "stopped" }.count, 1)
        XCTAssertEqual(reports.positions.compactMap { $0 }, reports.positions.compactMap { $0 }.sorted())
        XCTAssertEqual(reports.positions.last, 60_000)
    }

    func testMultipartUnknownWholeDurationNeverReportsPartAsMovie() async {
        var movie = item()
        movie.additionalPartKeys = ["/library/parts/2/file.mp4"]
        let api = RecordingPlexReporting(); let clock = Clock()
        let t = PlaybackTracker(item: movie, seekOffset: 0, plexAPI: api, clock: {clock.now},
                                automaticallySchedulesTimer: false)
        t.onPlaybackReady(); t.onPlaybackUpdate(positionSeconds: 0, state: .playing, durationSeconds: 30)
        clock.now = 25; t.onPlaybackUpdate(positionSeconds: 25, state: .playing, durationSeconds: 30)
        t.onTimelineTick(); await t.waitForPendingReports()
        let unknown = await api.snapshot()
        XCTAssertTrue(unknown.states.isEmpty)
        XCTAssertEqual(unknown.marks, 0)
        // A measured whole-stack duration unlocks a truthful aggregate position.
        clock.now = 45
        t.onPlaybackUpdate(positionSeconds: 45, state: .playing, durationSeconds: 60, durationIsWholeItem: true)
        await t.waitForPendingReports()
        let known = await api.snapshot()
        XCTAssertEqual(known.states, ["playing"])
        XCTAssertEqual(known.positions, [45_000])
        XCTAssertEqual(known.marks, 1)
    }

}
