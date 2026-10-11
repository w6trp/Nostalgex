# Dev log

Why things changed, and what state they were left in. Newest first.
Commits carry the detail of *what*; this carries the *why*.

## 2026-10-11 (Plex activity verification preparation)

**Shipped.** No replacement app installed and no reporting preference changed. The physical device remains on CouchWave 1.0.25 (46), source `f508c21` with local signing configuration.

**Changed.** Confirmed upstream main still points to `c2f32e6`. The installed source adds four commits over that base. Documented the current history-writing flag semantics and reviewed the official Plex timeline/status API. Prepared a scoped read-only observer and isolated test protocol, including before/during/after metadata, session and history comparisons. Corrected older documentation that still described device signing as unverified.

**Validation.** Seven synthetic observer tests pass. Installed source CI also passed channel engine, web and native tests. No server credentials were accessed, no test account was created, and no live timeline/scrobble or history experiment ran.

**Half-done.** Plex documentation provides no verified history-suppression parameter. Bunny Ears TV's developer-published settings screenshot confirms a position-free Heartbeat Only mode, providing a concrete test lead. Its private implementation and persisted-state effects remain unknown. A disposable test profile, sample items and authorized observation access have not been established. The prepared tool cannot prove behavior without that isolated experiment.

**Next.** Obtain exact authorization for existing disposable profile/sample data, or separately for creation of a named limited-access test profile. Run the reporting-off control first. Keep the real-account history switch off.

## 2026-10-11 (CouchWave artwork and device installation)

**Shipped.** CouchWave 1.0.25 (46) was signed, installed and launched on a paired physical Apple TV 4K (2nd generation) running tvOS 27.0. Both app and Top Shelf provision with the same App Group using development signing. No App Store, TestFlight or website deployment occurred.

**Changed.** Original couch-surfing artwork replaces the provisional beta graphics in the icon, Top Shelf, native headers and browser tuner. Browser sign-in and server-client names use CouchWave. Displayed channel names use CouchWave while their stable IDs remain unchanged. Browser links no longer imply that upstream's App Store app or donation accounts belong to this fork. Asset originals, generation prompts and the size-export script are checked in. Upstream MIT credit remains visible.

**Validation.** Xcode 27 signed build succeeded, strict recursive codesign verification passed, device installation and process launch succeeded. JavaScript checks and the production web build passed. Earlier native simulator validation passed 464 tests with 2 opt-in live-server tests skipped. No live media-server state was tested or changed.

**Half-done.** Changes remain on `codex/reliability-and-plex-privacy`. Remote navigation, actual playback and live Top Shelf behavior require owner hardware acceptance. Personal development profiles expire after seven days and require a fresh signed install. Local owner-specific Xcode signing selections are intentionally not committed. Historical upstream marketing pages are not a CouchWave release site.

**Next.** Test sign-in, channel surfing and remote focus on the device with history/resume reporting off. No verified Plex activity-only reporting path is enabled. Keep upstream history and legal credit when extending the branding to a future public website.

## 2026-10-11 (CouchWave beta identity)

**Shipped.** No signed build, TestFlight upload or website deployment. Changes remain on `codex/reliability-and-plex-privacy` for the personal fork.

**Changed.** The native beta is named CouchWave, with its own bundle IDs, App Group, keychain service, URL scheme and media-server client identity. A code-rendered wordmark and beta artwork replace upstream branding in the Apple TV interface. Upstream rating links are hidden until the fork has its own App Store record. Upstream signing team and export profiles are replaced with explicit owner setup requirements. MIT license and attribution remain, including a visible attribution in settings. Internal project/module names and the historical website remain unchanged for upstream compatibility.

**Validation.** Local Xcode 27.0 compiled the unsigned physical-tvOS target. The tvOS 27 simulator suite passed 464 tests; 2 opt-in live-server tests were skipped, with no failures. Built bundle IDs and the CouchWave display name/URL scheme were inspected. No live server state was tested or changed.

**Half-done.** Apple signing and physical-device pairing/installation remain unverified. Beta artwork is provisional. The website and browser tuner retain their upstream identity pending a separate web release.

**Next.** Select the owner's signing team and verify provisioning for both app and Top Shelf. Pair the intended Apple TV, install the approved development build, and perform hardware acceptance with history/resume reporting left off.

## 2026-10-11 (fork reliability branch)

**Shipped.** Source changes prepared on `codex/reliability-and-plex-privacy` for
review in the personal fork. No signed app, TestFlight upload or website deployment.
Upstream main, license and attribution are preserved.

**Changed.** Playback attempts now own their watchdog/cancellation work and guard
callbacks by current player item, so superseded recovery cannot take over a new
tune. Selected versions, multipart indices and exact source durations survive
conversion and enrichment; parts share one tracker. Audio selection returns after
recovery and capped fallback never increases the selected quality. Scheduled block
deadlines retune against the authoritative guide. Diagnostic credentials are
redacted before storage/logging, and old diagnostic rows are discarded.

Reporting now uses actual playback state/position with ordered, acknowledged
writes. A new explicit history/resume opt-in defaults off rather than inheriting
the old ambiguous activity preference. Plex timeline uses POST and watched marking
uses PUT with the rating key. No verified session-only mode is enabled: timeline
updates may still change history/resume state. Unknown multipart totals are not
reported as if an individual disc were the whole film.

Server-qualified identities prevent collisions in pools, caches and browser
schedules. Incomplete background refreshes preserve the working lineup. Calendar
boundaries cover 23/25-hour days and partial blocks retain their source offsets.
Canceled auth/enrichment cannot commit stale state. Top Shelf uses the item's own
server, keeps token URLs out of shared snapshots, handles channel links and clears
on sign-out. Movie/TV enrichment keys are distinct; remote cache v2 requires an
explicit fork-owned table. Upstream telemetry identifiers are removed.

Browser fixes cover failed-item rescheduling, stale async callbacks, codec-aware
source selection, credential-free library caches and exit cleanup. Developer tools
retain TLS checks, bind loopback by default and require explicit authenticated LAN
access. They reuse the shared scheduling engine. Newsletter segment failures are
surfaced. Apple release scripts require owner configuration and explicit upload.
The CI simulator toolchain is pinned; fork testing/signing instructions and a
remaining-concerns matrix are in `docs/FORK-TESTING.md` and `docs/FIX-STATUS.md`.

**Verified locally.** JavaScript suite including 26 reliability regressions and
Vite production build pass. Isolated native production-source checks pass: 27
playback/source/quality checks, 9 diagnostic checks, 13 reporting scenarios and 24
core scheduling/metadata/Top Shelf store assertions. Swift parsing, plist lint and
diff checks pass. Native probes use synthetic data and shims; they do not validate
AVPlayer, SwiftUI or Apple extension execution.

**Verified in CI.** [Run 38155433349](https://github.com/w6trp/Nostalgex/actions/runs/38155433349) passed on source commit
`3cf55f1072c4ddf6e1e711b0507d0990411f1143`: Xcode 26.6 compiled the app and
ran NostalgexTests on the Apple TV simulator, with 464 passed and 2 opt-in live
harnesses skipped. Web tests and production build passed too. Standard public
GitHub-hosted runners were used; no paid runner or artifact upload was configured.

**Half-done.** Full local tests cannot start because only Command Line Tools are
installed. Native hardware/server behavior is unverified.
Time-restriction programming semantics and the credential recovery mirror remain
unchanged pending a deliberate policy and durable-storage design. Advanced server
track selection and complete device codec capabilities are not claimed solved.

**Next.** Install the matching local Xcode/tvOS components, configure fork-owned
signing identifiers, then pair and test an Apple
TV. The owner must complete Apple account/agreements and choose the new product
identity. History-free active-session reporting needs an explicitly authorized
isolated server experiment before it can be enabled.

## 2026-10-09 (app)

**Shipped.** Nothing to Apple. 1.0.24 (45) is still in TestFlight beta review.
`main` now carries 1.0.25 (46), not archived or uploaded.

**Changed.**

- Jellyfin and Emby connect forms have a FIND SERVERS ON MY NETWORK button
  (`LANServerDiscovery.swift`). UDP 7359, `who is JellyfinServer?` and
  `who is EmbyServer?`, three second listen, deduped by server id, kind taken
  from which probe the server answered. Measured before writing it: the Emby
  under test answered the subnet directed broadcast and ignored
  255.255.255.255, so the app sends to both, computing the directed broadcast
  from every live IPv4 interface. Network.framework could not receive the reply
  (a connected UDP socket drops datagrams from the server's unicast address),
  so it is a BSD socket with SO_BROADCAST. No system prompt seen in the tvOS 26
  simulator; `NSLocalNetworkUsageDescription` now names all three servers in
  case hardware asks. Jellyfin side verified only as far as the parser, no
  Jellyfin server was on the test network. Plex skipped on purpose: that form
  has no address field.
- The Plex to Emby switch bug from the 2026-10-08 entry is fixed, and the cause
  was not either suspect named there. It was a race: a stale snapshot starts a
  background Plex refresh at launch, which on a large library runs for minutes;
  the user disconnects and signs into Emby meanwhile; Emby's scan finishes
  first; then the Plex scan returns and, with nothing checking that its sign-in
  still exists, rebuilt every pool from Plex items and saved the snapshot under
  the Emby identity. That poisoned snapshot is why it survived relaunch. The
  harness (`BackendSwitchScheduleTests.swift`) showed the clean switch passing
  on the old code and the race failing with "CH 7 VHS VAULT schedule would send
  18 Plex key(s) to Emby". Fix: a session generation bumped on Disconnect or a
  server change, checked before every commit in `loadLibrary` and used to abort
  the remaining requests; items from servers not signed in are dropped at load;
  a snapshot holding such items is refused on launch and rescanned; playback
  skips a foreign item with the failure card instead of sending the server a
  request it will answer 500. Disconnect now also clears today's manifests and
  the collection scan. Behaviour change: disconnect and re-sign-in to the same
  server reshuffles today's guide.
- Settings: Connection moved above Display and took in the report-playback
  switch (it had its own section). The two subtitle switches became one
  SUBTITLES row cycling Off, Foreign audio, Always: the fullscreen switch only
  ever overrode the foreign-audio one, so they were one three-way setting.
  Subtitle language only shows when subtitles are not Off. The Buy Me a Coffee
  and update-email QR codes are gone from Settings, with their analytics event.
  The in-player panel still has separate CC and auto buttons.
- `NostalgexTests`: 436 passed, 0 failed, 2 skipped on the merged tree
  (417 before, 9 discovery, 9 backend switch, 1 moved).

**Verified on hardware** (Apple TV 4K, first generation): RESCAN LIBRARY on a
Plex library of about 11,600 items, Disconnect mid scan, then Emby found via FIND
SERVERS. The log read "sign-in changed while the scan was running, discarding its
results", the Emby library loaded, and five programmes played with no HTTP 500s.
The automatic background refresh that started the original report was not
reproduced (the snapshot was only hours old) but runs through the same check. No
local network prompt appeared; a clean install is still the true first press.
A 4K HEVC title with EAC3 audio that stalled in the simulator played cleanly.

**Next.** 46 to TestFlight. App Store
listing for the next submission: "131 themed channels across 14 bundles" and
new screenshots. Discussion #2 (Fire TV fork): ordering and DayPacker ports match
the JS reference byte for byte; the channel filter does not (22 channels
diverge), asked the contributor for filter golden vectors in `scripts/` before
deciding where it lives. Discussions #8 (Roku) and #14 (languages) are
unanswered.

## 2026-10-09

**Shipped.** nostalgex.app: the four SEO blog drafts and table styling (#15),
then site wide SEO and speed work (#16). The buddy cop post went live a day
early; the other drafts each moved up a day (Oct 12, 14, 16, 19, 21) and still
need their `draft: true` removed on the day. No app change.

**Changed.**

- Hero text no longer waits for JavaScript. `.hero-copy` (and `.hero-shot`) on
  `/`, `/plex`, `/jellyfin` and `/emby` lost the `reveal` class, which kept them
  at opacity 0 until `app.js` ran. That was most of the mobile LCP.
- Hero media is lighter and off the critical path. New poster
  `guide-hero-1280.webp` (54 KB, was 511 KB) is preloaded; the video is
  `preload="none"` and `app.js` starts it after `load`, never under reduced
  motion or Save Data. New encodes: 480p mp4 412 KB (phones), 1600 webm 1.46 MB
  and 1280 mp4 1.37 MB (desktop). Old files stay for one release so cached
  pages don't 404. Screenshots below the hero get 1280 and 1920 `srcset` sizes.
- Lighthouse mobile, local static build, same machine before and after: `/`
  went 71 to 96 (LCP 6.3 s to 2.4 s, 1,068 to 745 KiB), `/jellyfin` 74 to 94
  (LCP 8.1 s to 2.3 s). Not yet measured on the Vercel preview.
- `/plex`, `/jellyfin` and `/emby` were near copies, and two of them sat outside
  Google's index. Each now has its own H1, direct answer, setup steps, tips and
  gotchas, and six server specific FAQs.
- Every page has new titles and descriptions, a 1200x630 card image
  (`og-image-1200.png`, letterboxed because a center crop clipped the logo), a
  48px favicon, an apple-touch-icon, and one JSON-LD `@graph` linking the app,
  Chad and Muell Haus by `@id`. Visible FAQs and FAQPage text are generated from
  the same strings.
- Blog: titles end in " | Nostalgex", Article author is the Person `#chad`,
  posts get a BreadcrumbList, and new optional front matter `cover_alt`. FAQPage
  and table wrapping from #15 are kept, folded into the single graph.
- Sitemap entries carry `lastmod` only (Google ignores changefreq and priority).
  Added `public/llms.txt`.
- Support page CORS configs said `https://nostalgex.app`, but the tuner runs on
  `https://www.nostalgex.app`, so the documented config could not work. Fixed.
- Removed the Data Haus analytics script from every page, the blog template and
  the CSP. statsngraphs stays. The privacy page, README and the support FAQ
  now describe one analytics script; the support FAQ no longer says there are
  no analytics on the tuner pages, because the connect page loads one.
- "Over a hundred" is now 131 everywhere it appeared.
- `Nostalgex/PRIVACY_POLICY.md` matches the privacy page: statsngraphs only,
  effective October 9. `docs/FAQ.md` named 1.0.22 for the Tailscale/VPN http fix,
  which shipped in 1.0.23 (support page was already right).

**Half-done.** Rich Results Test and a Lighthouse run against production still
need doing.

**Next.** Merge #15 first, then this. After deploy, resubmit the sitemap and
request indexing for /plex, /jellyfin, /support and the blog post.

## 2026-10-08

**Shipped.** 1.0.23 reached the App Store (build 44). It carries the Jellyfin
channel-change fix, the Plex playback fixes, the SCREAM and TIS THE SEASON
packages, eleven new channels and the Y2K renames. The web tuner on
nostalgex.app shipped separately the same day.

**Changed.**

- Merged #5 and #7 from @Gorbataras, who found the tune-in bug independently and
  traced it further than we had, through Jellyfin's `DynamicHlsController` across
  10.10.7, 10.11.0, 10.11.11 and 12.1. #5 routes **Emby** through the same
  client-side seek Jellyfin already used, and deletes `addingStartTime`, which no
  longer had a caller. #7 stops Jellyfin and Emby direct-playing the two things
  AVPlayer will not render: HEVC in MP4 tagged `hev1` (it renders only
  `hvc1`/`dvh1`) and 10-bit H.264. Both guards already existed on the Plex path
  and had never been ported.
- Closed #3. The symptom was the tune-in bug, fixed in 1.0.23 and verified by
  @Gorbataras on an Apple TV 4K against Jellyfin 12.1.
- **Plex adaptive mode is no longer requested.** With `autoAdjustQuality=1`, any
  film where the server re-encodes both video and audio came back as 3-second
  segments: the first eight arrived at full speed, then one every 6.1 seconds for
  the rest of the film. tvOS 26 abandons a segment that slow (CoreMedia -15628)
  and the picture died at 24 seconds, at 4K and at the 1080p retry alike. With it
  off, the same request returns 1-second segments and keeps pace. Audio-copied
  streams were never affected, which is why some channels played and others did
  not.
- **Dolby Vision profile 5 plays on Plex.** Plex refuses to re-encode DV5
  (decision 2003), but it will remux it for a client it resolves as Generic,
  which is what Plex's own Apple TV app gets: `container=mp4, video=copy hevc
  DOVI 5`. On a DoVi refusal the app now re-asks once that way. Measured on
  device: picture in 1.8s, 61.6s of playhead across a 60s hold, zero stalls, zero
  dropped frames.
- **A starving stream steps down instead of freezing.** When a server cannot keep
  up, the same film is re-requested from the current position capped at 1080p,
  and only a starving capped stream advances. Previously it froze or jumped to
  the next programme.
- **An offset HLS transcode reports the remainder as its duration**, not the full
  runtime. The end-of-item fallback was adding the offset back, so `remaining`
  went negative on every tuned-in transcode and the first rate-0 moment skipped
  to the next film.
- **Web tuner: a failed stream retried forever.** The hls.js error handler
  guarded its one recovery with a flag written onto the error payload, and hls.js
  builds a fresh payload per event, so the guard never held. Measured against a
  playlist of 404s: **14,612 requests in 8 seconds**, roughly 1,800/s aimed at
  the user's own server; the same handler with the flag held outside the event
  made 14. A real session was caught making 2,239 requests for one dead segment
  while an unrelated channel played normally.
- **Web tuner: each playback now mints its own Plex transcode session** and
  releases it on the way out. Without one, Plex keyed the transcode off the
  client id alone, so every channel change quietly repurposed the previous
  session, which is what left the old loader requesting segments that 404.
- **Web tuner: a manifest that will not load now skips.** `start.m3u8` answering
  400 produces exactly one fatal `manifestLoadError` and nothing after it, so
  `startLoad()` had nothing to retry and the channel sat on black indefinitely.
  It now says so and moves to the next programme, stopping after three failures
  in a row because that points at the server rather than the file.
- **Music video genres come from Deezer** when the server reports none. On a test
  library of 1,131 music videos only 148 carried a genre, and MusicBrainz tags
  filled almost none of the rest, which is why CALIENTE and HEADBANGERS sat
  empty. Deezer resolved 47 of a random 60, and a filename cleaner (underscores,
  scene tags, `ft.`/`feat.`) recovered 10 of the 13 misses.
- **Music video years** are read from the filename first, then MusicBrainz, then
  the server only when plausible. Servers commonly report 1970 or the date the
  file was added, and Deezer's year is the album's, wrong on 15 of 15 sampled, so
  the decade channels were sorting by the wrong year.

**Changed, evening session (real hardware).** Build 1.0.24 (45) ran on an Apple TV HD
(tvOS 26.6) and an Apple TV 4K simulator against an Emby 4.10.1.0 server. Everything below
was measured there, not inferred.

- **Issue #6 confirmed fixed on hardware, with a controlled before/after.** The shipped
  1.0.23 (44) from TestFlight on the same device: `HTTP 404. The file '/UserViews' could
  not be found.` Build 45 ten minutes later: `[Emby] LIBRARY: 1541 items`, 69 channels,
  playback at a 57-minute mid-schedule join. Gorbataras's #5 Emby seek is confirmed by the
  same run.
- **The guide wrap works on tvOS 26.6**, the reporter's exact version, which the 26.1
  simulator could never reproduce. Down wraps, Up reaches SETTINGS.
- **The failure card now says why, accurately.** Three classifier corrections from
  watching it misfire: the probe walks master to variant to first segment, because the
  master answers 200 while every segment beneath it is refused; CoreMedia -12889 (no
  response in 3s) and -15628 (segment abandoned) classify as the server being too slow,
  not the device failing to decode; and a decoded frame vetoes "Apple TV couldn't play
  this file" outright. Verified verdicts on hardware: `Emby HTTP 500, refused before
  video` and `Emby below real time on the capped stream`.
- **Audio track selection.** Jellyfin and Emby hand back the file's default track, and
  Joe Dirt's default is Spanish 2ch with English 5.1 unflagged, so it played in Spanish
  on a channel with no picker. The resolver now reads MediaStreams from PlaybackInfo,
  prefers a track in the viewer's language with the most channels, then the default,
  then the first, and pins `AudioStreamIndex` on the transcode URL. Verified against the
  server: Emby's own URL pinned index 1 (spa); ours pins 2 (eng); Emby accepts it. 7 tests.
- **The starvation ladder's Emby rung fired for real** (The Wedding Singer, 13 Going on
  30): starve, cap to 1080p, `TRANSCODE READY`. It recovers what it can.

**Found, not fixed.**

- **Switching backend keeps the old day schedule.** A device signed into Plex, then
  Disconnected and connected to Emby for the first time, kept playing the Plex running
  order: Plex rating keys sent to Emby resolve to Person records and 500, every channel,
  looping between two titles indefinitely. A fresh install is flawless, so it is the
  transition that leaks. `DailyManifestStore.clearAll` on Disconnect uses the fingerprint
  current at that moment, and `apiForServer` never checks an item's `serverID` belongs to
  the connected backend. Workaround: delete and reinstall. Worth fixing before a wide push.
- **Two test rigs invent failures.** The tvOS simulator has no EAC3/AC3 decoder, so ~25%
  of a typical library stalls 3s in and looks like starvation; the Apple TV HD has no HEVC
  decoder, so every HEVC title forces a server re-encode that held 1.07x here against
  CoreMedia's 3s first-segment patience. The same file for an HEVC-capable client is a
  17.3x remux. Playback claims need the 4K unit.
- **On this Emby, 10-bit sources cannot transcode at all.** `VideoFilters.format..ctor()`
  throws "An item with the same key has already been added. Key: threads" before ffmpeg
  starts; 190 of 1541 movies affected. Ruled out by measurement with the server restored
  afterwards: codec, resolution, bitrate, subtitles, audio stream, thread count, hardware
  acceleration. A server bug, reported by the card as a refusal, nothing for the app to do.

**Half-done.**

- `fix/emby-userviews-404` — **Emby library scans fail immediately.**
  `loadSections` asked for `/UserViews?userId=`, which is Jellyfin's spelling.
  Measured against Emby Server 4.10.1.0: `/UserViews` answers 404,
  `/Users/{id}/Views` answers 200. It is the first request after sign-in, so it
  fails whatever the libraries are named and however large they are. Fixed with
  three tests on the branch, not yet merged. This is issue #6, and it is present
  in the released 1.0.23. **Now verified end to end against an Emby server**
  (see below).
- `feat/playback-failure-card` — **a programme that will not play now says why,
  instead of being swapped for the next one in silence.** Only three of about eight
  failure paths showed any UI at all; the startup watchdog, the starvation verdict and an
  AVPlayer item reaching `.failed` all advanced with nothing on screen, which reads as a
  broken app and hides whether the person should look at their server or at the file.
  `PlaybackState.error` now carries a `PlaybackFailure` rather than a sentence, and every
  failure path funnels through one place that records the verdict, emits the matching
  analytics code and shows a card for five seconds before advancing. Amber when the server
  is the thing to go and look at, red when the file or the device is.
  Getting the reason right needed a new source of truth: tvOS has no `httpStatusCode` on
  `AVPlayerItemErrorLogEvent`, so the status of a refused segment cannot be read out of the
  player, and that status is the difference between "your server refused this" and "this
  file will not decode". `StreamFailureProbe` asks the server instead, with one ranged GET
  on the URL that just failed. 14 tests, classification being a pure function over what was
  observed. Not merged.
- The startup watchdog's capped retry had the same missing client-side seek the starvation
  ladder got, so a watchdog retry on Jellyfin or Emby would have restarted the film from
  frame one. Fixed on the same branch as the ladder.
- `fix/starvation-ladder-all-backends` — **the starvation ladder had no rung on
  Jellyfin or Emby, so one stall skipped the programme.** `handleStarvation` steps
  a starving stream down to 1080p and only advances once there is nothing smaller
  to ask for, but `cappedTranscodeURL` was implemented on Plex alone and the
  `MediaBackend` default returns nil. Measured on Emby Server 4.10.1.0: each
  6-second segment took 3.4s to produce before its first byte, at 128 Mbps once
  flowing, so the server and not the network was the limit; a film jumped out
  mid-scene to the next scheduled title at its first frame. Both backends now
  build the rung at 1920 wide and 8 Mbps under their own `PlaySessionId`, with no
  start time on the URL, because the segment handler refuses one. A new
  `cappedStreamStartsAtOffset` says which backends seek client-side. 4 tests.
  Not merged.
- `fix/backend-error-copy` — error messages name the server the user actually
  connected to. `PlexAPIService.APIError` is the shared error type for all three
  backends, but every message hung off it was written for Plex, so an Emby user
  whose scan 404s was told "Plex (or your network path) returned HTTP 404" and
  sent to check Plex's Remote Access setting. Plex keeps its own copy, including
  the `/library` and `/identity` paths only Plex serves. One test asserts no
  Jellyfin or Emby message contains the word "Plex", across every error case.
  Not merged.
- `fix/guide-wrap-scrolling` — the guide's vertical wrap now runs off a focusable
  sentinel row just outside the last channel rather than a 150ms staleness timer,
  so "ran off the end" is proven by the focus engine instead of inferred from a
  clock. Up out of channel one deliberately still leaves for SETTINGS and does
  not wrap. 9 UI tests. Not merged. The report that prompted it came from tvOS
  26.6 and never reproduced on the 26.1 simulator at any list length or cadence,
  so treat this as hardening fragile timing rather than a confirmed fix.
- The web tuner still appends `StartTimeTicks` to its Jellyfin fallback URL in
  `getJellyfinTranscodeUrl` (`plex-tuner.html`). Same defect #5 fixed on tvOS.
  hls.js already seeks via `startPosition`, so the parameter only breaks segment
  requests. Spotted by @Gorbataras. In progress.
- **Emby, measured.** The Emby halves of #5 and #7 were reasoned from Jellyfin's
  HLS controller being forked from Emby's, and from Emby's own web client seeking
  client-side. Both now ran against Emby Server 4.10.1.0: sign-in, library scan,
  guide build, and a mid-programme join that started Heat at 47 minutes into a
  2:50:00 film and advanced 25s of playhead across 25s of wall clock with no
  stall. The scan only ever touches `/Users/{id}/Views` and `/Items`, and series
  and episodes go through that same `/Items` call with a different
  `IncludeItemTypes`, so a movies-only test library still exercises every HTTP
  path the scan makes. What remains untested on Emby is episode *parsing*, not
  whether an endpoint answers.

**Next.**

- Merge the three branches above.
- Port the web tuner's `StartTimeTicks` removal.
- Exercise an Emby library that contains TV series, to cover episode parsing and
  the per-show grouping the movies-only run could not reach.
