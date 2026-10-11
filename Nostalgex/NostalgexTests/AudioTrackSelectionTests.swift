import XCTest
@testable import Nostalgex

/// A retro TV guide has no audio picker, so it has to pick the right track itself.
///
/// Jellyfin and Emby hand over whichever track the file marks default, and plenty of
/// files mark a dubbed one. Measured 2026-10-08: Joe Dirt played in Spanish on a channel
/// with no way to change it, because the file's default is
/// `spa 2ch "Spanish [Latinoamericano]"` and its English 5.1 track is not the default.
final class AudioTrackSelectionTests: XCTestCase {

    private typealias Stream = JellyfinPlaybackResolver.PlaybackInfoResponse.MediaStream

    private func stream(_ index: Int, _ type: String, lang: String?, isDefault: Bool = false,
                        channels: Int? = nil) -> Stream {
        // Decoding through JSON exercises the real coding keys, including the "Type"
        // key Swift will not let a property be named after.
        let json = """
        {"Index": \(index), "Type": "\(type)", \(lang.map { "\"Language\": \"\($0)\"," } ?? "")
         "IsDefault": \(isDefault), \(channels.map { "\"Channels\": \($0)," } ?? "") "x": 0}
        """
        return try! JSONDecoder().decode(Stream.self, from: Data(json.utf8))
    }

    /// The exact Joe Dirt layout.
    func testEnglishBeatsADefaultFlaggedSpanishTrack() {
        let streams = [
            stream(0, "Video", lang: nil),
            stream(1, "Audio", lang: "spa", isDefault: true, channels: 2),
            stream(2, "Audio", lang: "eng", isDefault: false, channels: 6),
        ]
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["en-US"]), 2)
    }

    func testMoreChannelsWinsAmongTracksInTheViewersLanguage() {
        let streams = [
            stream(1, "Audio", lang: "eng", isDefault: true, channels: 2),
            stream(2, "Audio", lang: "eng", channels: 6),
        ]
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["en"]), 2,
                       "a 5.1 English mix beats a stereo English default")
    }

    /// "en-GB" must match a track tagged "eng"; three-letter and two-letter codes both occur.
    func testLocaleIdentifiersMatchThreeLetterTags() {
        let streams = [
            stream(1, "Audio", lang: "fre", isDefault: true),
            stream(2, "Audio", lang: "eng"),
        ]
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["en-GB"]), 2)
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["fr-CA"]), 1,
                       "a French viewer keeps the French track")
    }

    func testFallsBackToTheFilesDefaultWhenNoTrackIsInTheViewersLanguage() {
        let streams = [
            stream(1, "Audio", lang: "jpn"),
            stream(2, "Audio", lang: "kor", isDefault: true),
        ]
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["de"]), 2)
    }

    /// One track is not a choice. Leaving the index nil keeps the server's URL untouched,
    /// which matters: most files have one track and must not get a needless parameter.
    func testASingleAudioTrackIsLeftToTheServer() {
        let streams = [stream(0, "Video", lang: nil), stream(1, "Audio", lang: "eng")]
        XCTAssertNil(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["en"]))
        XCTAssertNil(JellyfinPlaybackResolver.preferredAudioIndex(in: nil))
    }

    func testExplicitLanguageBeatsEnglishEvenWhenEnglishHasMoreChannels() {
        for (preferred, tag) in [("fr", "fra"), ("es", "spa"), ("nl", "dut")] {
            let streams = [stream(1, "Audio", lang: tag, channels: 2),
                           stream(2, "Audio", lang: "eng", isDefault: true, channels: 6)]
            XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: [preferred]), 1)
        }
    }

    func testOrderedLanguagesDoNotBecomeAnUnorderedSet() {
        let streams = [stream(1, "Audio", lang: "fra", channels: 2), stream(2, "Audio", lang: "eng", channels: 6)]
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["fr", "en"]), 1)
        XCTAssertEqual(JellyfinPlaybackResolver.preferredAudioIndex(in: streams, preferredLanguages: ["en", "fr"]), 2)
    }

    func testLocalAudioUsesCanonicalTagsAndLeavesUnmatchedDefaultAlone() {
        XCTAssertEqual(AudioLanguageSelection.preferredOptionIndex(tags: ["eng", "spa"], preferredLanguages: ["es-MX"]), 1)
        XCTAssertEqual(AudioLanguageSelection.preferredOptionIndex(tags: ["eng", "dut"], preferredLanguages: ["nl"]), 1)
        XCTAssertNil(AudioLanguageSelection.preferredOptionIndex(tags: [nil,"und"], preferredLanguages: ["en"]))
        XCTAssertNil(AudioLanguageSelection.preferredOptionIndex(tags: [], preferredLanguages: ["en"]))
    }

    func testSavedLanguageOverridesSystemForServerStreamSelection() throws {
        let suite = "audio-language-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AudioLanguageSelection.preferredLanguages(defaults: defaults, systemLanguages: ["en-US"]), ["en-US"])
        defaults.set("es", forKey: AudioLanguageSelection.defaultsKey)
        let languages = AudioLanguageSelection.preferredLanguages(defaults: defaults, systemLanguages: ["en-US"])
        XCTAssertEqual(languages, ["es"])
        let json = #"{"MediaSources":[{"Id":"source","TranscodingUrl":"/stream.m3u8?AudioStreamIndex=2","MediaStreams":[{"Index":1,"Type":"Audio","Language":"spa","Channels":2},{"Index":2,"Type":"Audio","Language":"eng","IsDefault":true,"Channels":6}]}]}"#
        let info = try JSONDecoder().decode(JellyfinPlaybackResolver.PlaybackInfoResponse.self, from: Data(json.utf8))
        let result = try XCTUnwrap(JellyfinPlaybackResolver.resolve(info, serverURL: "https://synthetic.invalid", apiKey: "fixture", itemId: "1", mediaSourceId: "source", preferredLanguages: languages))
        let query = URLComponents(url: result.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "AudioStreamIndex" }?.value, "1")
        defaults.set("__system__", forKey: AudioLanguageSelection.defaultsKey)
        XCTAssertEqual(AudioLanguageSelection.preferredLanguages(defaults: defaults, systemLanguages: ["fr-CA"]), ["fr-CA"])
    }

    func testPinningReplacesAnyIndexTheServerAlreadyChose() throws {
        let url = URL(string: "http://h:8096/videos/1/master.m3u8?MediaSourceId=m&AudioStreamIndex=1&api_key=k")!
        let pinned = JellyfinPlaybackResolver.pinningAudioStream(url, index: 2)
        let q = try XCTUnwrap(URLComponents(url: pinned, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(q.filter { $0.name == "AudioStreamIndex" }.map(\.value), ["2"])
        XCTAssertTrue(q.contains { $0.name == "api_key" && $0.value == "k" }, "other params survive")
    }

    func testPinningWithNoIndexLeavesTheURLAlone() {
        let url = URL(string: "http://h:8096/videos/1/master.m3u8?api_key=k")!
        XCTAssertEqual(JellyfinPlaybackResolver.pinningAudioStream(url, index: nil), url)
    }
}
