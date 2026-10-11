import Foundation
import Testing
@testable import Nostalgex

@Suite("Core identity and calendar reliability", .serialized)
struct CoreReliabilityTests {
    private func item(_ key: String, server: String, minutes: Int = 60) -> PlexMediaItem {
        PlexMediaItem(id: "\(server):\(key)", title: "\(server) movie", artist: nil,
            episodeTitle: nil, seTag: nil, summary: "", year: 2000,
            originallyAvailableAt: nil, contentRating: nil, duration: minutes, ratingKey: key,
            partKey: nil, container: "mp4", videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0,
            type: .movie, thumb: nil, art: nil, viewCount: 0, addedAt: 0,
            studio: nil, tmdbID: nil, imdbID: nil, librarySource: .movie, serverID: server)
    }

    private func channel(_ id: Int, items: [PlexMediaItem]) -> Channel {
        Channel(id: id, number: id, name: "Fixture", color: .blue, category: nil,
                rules: nil, timeRestrictions: nil, minItems: 0, itemPool: items)
    }

    @Test @MainActor func poolRefreshPreservesServerIdentityInEitherOrder() {
        let a = item("42", server: "A"), b = item("42", server: "B")
        for items in [[a, b], [b, a]] {
            let result = MusicEnrichmentService().refreshChannelPools(
                [channel(1, items: [a]), channel(2, items: [b])], from: items)
            #expect(result[0].itemPool.first?.id == a.id)
            #expect(result[1].itemPool.first?.id == b.id)
        }
    }

    @Test func conflictingGuidePreservesPlayableNowAndIgnoresOtherServers() {
        let a = item("42", server: "A"), b = item("42", server: "B")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func schedule(_ media: PlexMediaItem) -> ChannelSchedule {
            let current = ScheduleEntry(id: "now-" + media.id, item: media,
                startTime: now.addingTimeInterval(-60), endTime: now.addingTimeInterval(3540), isNowPlaying: true)
            let next = ScheduleEntry(id: "next-" + media.id, item: b,
                startTime: current.endTime, endTime: current.endTime.addingTimeInterval(3600), isNowPlaying: false)
            return ChannelSchedule(entries: [current, next], nowPlaying: current,
                upNext: next, progress: 1 / 60, elapsedSeconds: 60)
        }
        var schedules = [1: schedule(a), 2: schedule(a), 3: schedule(b)]
        ChannelScheduleBuilder.resolveConflicts(&schedules)
        #expect(schedules[2]?.nowPlaying?.item.id == a.id)
        #expect(schedules[2]?.isCurrent(at: now) == true)
        #expect(schedules[2]?.nowPlaying?.isConflict == true)
        #expect(schedules[2]?.entries.filter(\.isNowPlaying).count == 1)
        #expect(schedules[3]?.nowPlaying?.isConflict == false)
    }

    @Test func calendarDaysCoverDSTWithoutGapsOrOverlap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        for (month, day, seconds) in [(3, 8, 23 * 3600), (11, 1, 25 * 3600)] {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let key = "core-dst-\(month)-\(UUID().uuidString)"
            defer { DailyManifestStore.clearAll(credentialFingerprint: key) }
            let start = calendar.startOfDay(for: date)
            let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
            let blocks = DailyManifestScheduler.blocks(for: channel(77, items: [item("1", server: "A")]),
                at: date, credentialFingerprint: key, calendar: calendar)
            #expect(end.timeIntervalSince(start) == Double(seconds))
            #expect(blocks.first?.startTime == start)
            #expect(blocks.last?.endTime == end)
            for (before, after) in zip(blocks, blocks.dropFirst()) { #expect(before.endTime == after.startTime) }
        }
    }

    @Test func partialBlocksPersistOffsetAndSeekIntoSource() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12)))
        let key = "core-offset-\(UUID().uuidString)"
        defer { DailyManifestStore.clearAll(credentialFingerprint: key) }
        let ch = channel(88, items: [item("42", server: "A"), item("42", server: "B")])
        let blocks = DailyManifestScheduler.blocks(for: ch, at: date, credentialFingerprint: key, calendar: calendar)
        let partial = try #require(blocks.first { $0.sourceOffsetSeconds > 0 })
        #expect(partial.durationSeconds + Double(partial.sourceOffsetSeconds) == 3600)
        DailyManifestScheduler.invalidateMemo()
        let restored = DailyManifestScheduler.blocks(for: ch, at: date, credentialFingerprint: key, calendar: calendar)
        #expect(restored.first { $0.startTime == partial.startTime }?.sourceOffsetSeconds == partial.sourceOffsetSeconds)
        let entry = ScheduleEntry(id: "partial", item: partial.item, startTime: partial.startTime,
            endTime: partial.endTime, isNowPlaying: true, sourceOffsetSeconds: partial.sourceOffsetSeconds)
        let schedule = ChannelSchedule(entries: [entry], nowPlaying: entry, upNext: nil,
            progress: 0, elapsedSeconds: partial.sourceOffsetSeconds)
        #expect(schedule.livePlayback(at: partial.startTime)?.elapsedSeconds == partial.sourceOffsetSeconds)
        #expect(schedule.livePlayback(at: partial.startTime.addingTimeInterval(10))?.elapsedSeconds == partial.sourceOffsetSeconds + 10)
    }

    @Test func movieAndTVMetadataIDsCannotAlias() {
        #expect(MediaEnrichment.cacheKey(mediaType: "movie", tmdbID: "42") !=
                MediaEnrichment.cacheKey(mediaType: "tv", tmdbID: "42"))
    }
    @Test @MainActor func topShelfNeverPersistsServerTokenAndDisconnectClearRemovesSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        TopShelfStore.containerURLOverride = directory
        defer {
            TopShelfStore.clear()
            TopShelfStore.containerURLOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        // A future card does not initiate any artwork request in this offline test.
        let future = Int(Date().timeIntervalSince1970) + 3600
        TopShelfStore.write(TopShelfSnapshot(generatedUnix: future, entries: [
            .init(channelID: 1, channelNumber: 1, channelName: "Fixture", title: "Fixture",
                  startUnix: future, endUnix: future + 3600,
                  imageURL: "https://fixture.invalid/thumb?X-Plex-Token=synthetic-secret")
        ]))
        let data = try Data(contentsOf: directory.appendingPathComponent("Library/Caches/topshelf.json"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("synthetic-secret"))
        #expect(!text.contains("fixture.invalid"))
        TopShelfStore.clear()
        #expect(TopShelfStore.read() == nil)
    }

    @Test func runtimeBundleCategoryCannotLeakIntoAnalytics() {
        #expect(AnalyticsChannelDescriptor.safeStaticBundle("private collection category") == "uncategorized")
        #expect(AnalyticsChannelDescriptor.safeStaticBundle("nostalgex") == "nostalgex")
    }

}
