import XCTest
@testable import Nostalgex

@MainActor
final class PlexActivitySyncTests: XCTestCase {

    func testHeartbeatAndHistoryAreMutuallyExclusive() {
        let defaults = UserDefaults.standard
        let keys = [AppState.syncPlexActivityDefaultsKey, AppState.plexHeartbeatOnlyDefaultsKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let state = AppState()
        XCTAssertFalse(state.plexHeartbeatOnly)
        state.syncPlexActivity = true
        state.plexHeartbeatOnly = true
        XCTAssertFalse(state.syncPlexActivity)
        XCTAssertTrue(state.heartbeatReportingActive)
        state.syncPlexActivity = true
        XCTAssertFalse(state.plexHeartbeatOnly)
        state.plexHeartbeatOnly = true
        state.backendKind = .jellyfin
        XCTAssertFalse(state.heartbeatReportingActive)
        XCTAssertFalse(state.syncPlexActivity)
    }

    // Never-touched installs must land on OFF: channel surfing otherwise floods the
    // household's Plex "Continue Watching" row with programs nobody chose to start.
    func testResolveSyncPlexActivity_defaultsOffWhenNothingStored() {
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: nil))
    }

    // An explicit choice always wins, in both directions, so flipping the default never
    // overrides a user who already decided.
    func testResolveSyncPlexActivity_honorsExplicitChoice() {
        XCTAssertTrue(AppState.resolveSyncPlexActivity(stored: true))
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: false))
    }

    // UserDefaults hands back NSNumber; a non-Bool value must not read as ON.
    func testResolveSyncPlexActivity_ignoresNonBooleanStoredValue() {
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: "yes"))
    }

    func testLegacySyncDoesNotOptIntoNewHistoryPolicy() {
        let defaults = UserDefaults.standard
        let currentKey = AppState.syncPlexActivityDefaultsKey
        let legacyKey = AppState.legacySyncPlexActivityDefaultsKey
        let current = defaults.object(forKey: currentKey)
        let legacy = defaults.object(forKey: legacyKey)
        defer {
            if let current { defaults.set(current, forKey: currentKey) }
            else { defaults.removeObject(forKey: currentKey) }
            if let legacy { defaults.set(legacy, forKey: legacyKey) }
            else { defaults.removeObject(forKey: legacyKey) }
        }
        defaults.removeObject(forKey: currentKey)
        defaults.set(true, forKey: legacyKey)
        let state = AppState()
        XCTAssertFalse(state.syncPlexActivity)
        XCTAssertEqual(defaults.object(forKey: legacyKey) as? Bool, true)
    }

    func testSyncPlexActivityToggle_persistsToUserDefaults() {
        let defaults = UserDefaults.standard
        let key = AppState.syncPlexActivityDefaultsKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let state = AppState()
        state.syncPlexActivity = true
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)

        state.syncPlexActivity = false
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
    }

    // With no Plex API the tracker must be completely inert: no timeline, no scrobble.
    // This is what makes the OFF default actually stop Continue Watching entries, since
    // AppState passes a nil API whenever sync is off.
    func testPlaybackTrackerWithoutAPI_neverScrobbles() {
        let item = PlexMediaItem(
            id: "1",
            title: "Test",
            artist: nil,
            episodeTitle: nil,
            seTag: nil,
            summary: "",
            year: 1988,
            originallyAvailableAt: nil,
            contentRating: nil,
            duration: 90,
            ratingKey: "1",
            partKey: "/library/parts/1/file.mkv",
            container: "mkv",
            videoCodec: nil,
            audioCodec: nil,
            videoProfile: nil,
            bitrate: nil,
            genres: [],
            rating: 0,
            userRating: 0,
            type: .movie,
            thumb: nil,
            art: nil,
            viewCount: 0,
            addedAt: 0,
            studio: nil,
            tmdbID: nil,
            imdbID: nil,
            librarySource: .movie
        )
        let tracker = PlaybackTracker(item: item, seekOffset: 0, plexAPI: nil)
        tracker.onPlaybackReady()
        tracker.stop()
        XCTAssertFalse(tracker.scrobbled)
    }

    func testServerWatchCount_usesPlayCountWhenTheServerHasOne() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 4, played: true), 4)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 3, played: false), 3)
    }

    func testServerWatchCount_playedWithNoCountStillCountsAsOneWatch() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 0, played: true), 1)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: true), 1)
    }

    func testServerWatchCount_unplayedIsZero() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: false), 0)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: nil), 0)
    }
}
