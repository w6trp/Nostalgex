# Native playback review status

## Confirmed defects and implemented fixes

| Defect | Fork status | Evidence and limits |
| --- | --- | --- |
| Recovery omitted preferred-audio selection and retained descriptors for an old player item. | Fixed before build 52: all initial/retry/fallback ready paths apply audio selection; replacement players clear stale descriptors. | Code paths and full native suite checked. Forced fallback with multilingual media still needs hardware acceptance. |
| Server audio selector unconditionally added English, ignored ordered preferences and treated three-letter language tags as their first two characters. Server HLS selection also ignored the explicit app language setting. | Fixed in build 53. Canonical matching and ordered preferences feed both local selection and Jellyfin/Emby HLS requests. | Extracted production code chose English for French, Spanish and Dutch fixtures before; all three choose the intended track after. New tests verify preference order, saved setting and actual AudioStreamIndex query. |
| A preferred local track was absent, but selection forced index zero rather than the existing default; an empty audible group was unsafe. | Fixed before build 52. | Current code checks empty options and keeps the selected/default option when no preferred language matches. No claim that every empty-group/device case occurred in the field. |
| A selected Plex media version became index zero during HLS/decision requests; later parts could replay part one or drop part three. Whole-film offsets were treated as part-local. | Fixed before build 52; build 53 extends complete stacks to multipart episodes. Upstream PR #21 is separate. | Parser/model/persistence/request tests cover identity, per-part codec facts, third parts, boundaries and missing-length fallback. Recognizable multi-file direct/HLS hardware acceptance remains open. |
| Old watchdogs and delayed resolvers could replace a healthy new channel/attempt; starvation could start concurrent recovery. | Fixed before build 52 with owned cancellation, generation/current-item guards, one recovery at a time and stale resolved-session cleanup. | Code and full suite checked. Real network-delay/recovery orchestration still needs hardware exercise. |
| Recovery quality could rise from Low/Medium to 1080p/12 Mbps. Capped retries could copy the same unrenderable video again. | Fixed before build 52: recovery ceilings do not exceed the selected tier, and the compatibility retry disables video direct stream. | Request/quality regressions pass. Server load and actual delivered encoding still depend on server decisions. |
| HLS capabilities advertised MPEG-4 Part 2 based on raw-file support; the broad HEVC gate allowed declared 12-bit video. | Conservative request/eligibility guards implemented before build 52. | Unit tests verify those policy decisions, not actual hardware decoding for every profile/container/display. |

## Open hardware and design questions

- Plex's server-generated HLS stream may omit the preferred audio track entirely. Selecting an AVFoundation option cannot recover an absent track. Explicit Plex audio/subtitle stream negotiation is separate work; it can restart transcoding and needs a reviewed policy for language, commentary, accessibility roles and burned subtitles.
- A video watchdog cannot reliably infer that audible output is working. Intentional silence, receiver/output routing, track selection and decoding failures need separate observations; automatic fallback based only on silence would be unsafe behavior.
- Full profile/level/frame-rate/chroma/HDR support depends on device, tvOS, container and display. No blanket support claim follows from unit tests. Sanitized failing-media metadata and a reproducible device example are needed.
- The existing preference within one language still favors more channels for server selection. This patch does not invent a new commentary/accessibility-track priority or change surround/downmix policy.
- Missing part durations keep the current fallback instead of guessing a whole-film-to-part mapping. Reliable seeking into such files requires better metadata or additional server probing.
- Forced termination, network loss and delayed Plex history persistence remain outside the completed heartbeat lifecycle observations.

## Validation

Build 53's full native suite passed 501 tests, with 2 optional live harnesses skipped. The signed device build succeeded. Build 52's sustained heartbeat run is documented separately in `PLEX-ACTIVITY-VERIFICATION.md`; it does not prove audio/codec acceptance. Private media metadata, credentials and audit exports are not committed.
