# Reliability branch status

Branch: `codex/reliability-and-plex-privacy`.
This is an implementation and offline-validation checkpoint, not a signed release
or a claim that every review concern has been resolved on hardware.

## Implemented fixes

| Area | Change |
| --- | --- |
| Native playback recovery | Own/cancel watchdog work, guard callbacks by generation and player item, coalesce fallback resolution, clean up stale sessions, and stop pending work on disconnect/background/sleep. |
| Plex source selection | Preserve selected media/part indices and per-part codec facts; retain remaining multipart files and audio selection across recovery. |
| Compatibility fallback | Do not raise the selected quality ceiling; force video conversion when copying cannot decode; reject concrete unsupported bit-depth/profile cases. |
| Multipart accounting | Keep one tracker and aggregate source positions across parts; use exact whole/part metadata and withhold multipart reporting when a reliable whole duration is unavailable. |
| Playback reporting | Use sampled playback state/position, ordered writes, server acknowledgement and rate-limited retries. Apply changes to reporting preference immediately. |
| Privacy defaults | Require a new explicit history/resume opt-in; do not silently migrate an old activity-sync opt-in. No verified history-free active-session mode is enabled. |
| Multi-server identity | Use server-qualified item identities for native pools/music caches and browser manifests, blacklist and caches. |
| Refresh and authentication | Preserve the working lineup when a background scan is incomplete; reject canceled/stale sign-in and music work. |
| Guide | Keep current programs authoritative when channels overlap; use calendar day boundaries and persist partial-block source offsets; enforce the selected native block deadline with guarded retuning. |
| Metadata cache | Separate movie and TV ID namespaces; support local/TMDB lookup without Supabase; require explicit fork-owned v2 remote-cache configuration. |
| Top Shelf | Build future entries, choose each item's server, cache local artwork instead of server-token URLs, handle links, and clear on disconnect. |
| Diagnostics | Redact sensitive URL/header material before persistence or logging and discard legacy unsafe diagnostic rows. |
| Telemetry | Remove upstream telemetry identifiers; limit category values to the known catalog vocabulary. |
| Browser lifecycle | Exclude failed programs before rescheduling, reject stale playback/subtitle responses, clear outgoing streams and avoid reusable credentials in the library cache. |
| Browser compatibility | Check codec support in addition to container and preserve chosen media/part indices. |
| Developer tools | Keep certificate validation enabled, bind loopback by default, and require explicit authenticated LAN access. Reuse the shared schedule engine. |
| Web services and release tools | Correct failed newsletter segment handling; remove upstream Apple account defaults and require explicit upload mode. |

## Validation scope

Offline checks use synthetic media and fake transports. The JavaScript test suite
and Vite production build run locally. Native Foundation/CryptoKit probes execute
production or directly extracted pure code for scheduling, metadata, tracker and
source-selection behavior. Swift syntax checks do not type-check the complete
tvOS app. Required full NostalgexTests, simulator and real-device tests still need
Xcode and the tvOS components. No real user's media or watch state was used.

See the latest [development log](DEVLOG.md) for measured results and
[fork testing guide](FORK-TESTING.md) for reproduction and device setup.

## Remaining concerns and decisions

- **Plex live visibility without retained history/resume:** no verified supported
  mode in the documented timeline API. Leave history sync off; a future experiment
  requires explicitly authorized disposable data and before/after server checks.
- **Native integration:** AVPlayer behavior, callback races, server negotiation,
  audio/subtitle output, remote focus and Top Shelf rendering still need Xcode and
  physical-device validation. Offline checks do not establish codec support on
  every Apple TV model.
- **Time restrictions:** upstream rules use the current clock and retain the
  original pool when fewer than two eligible items remain. They are programming
  preferences, not verified parental controls. A strict filtering policy and a
  time-aware guide horizon need an explicit product decision and fixtures.
- **Credential durability:** the upstream UserDefaults recovery mirror remains.
  Removing it without a tested durable alternative could lose sign-ins. Its local
  storage tradeoff is unresolved; this is not a claim of Keychain-only storage.
- **Advanced track/capability support:** arbitrary server-side audio/subtitle burn
  selection and a complete profile/level/chroma/HDR capability matrix remain
  enhancements. Local controls can choose only tracks actually provided.
- **Fork identity and signing:** choose a final name and configure owner-owned
  bundle IDs, App Group, URL scheme and Apple signing team before distribution.
  No name availability or trademark clearance has been performed.
- **Optional services:** no remote database migration, paid enrollment, signing
  credential creation, TestFlight upload or production web deployment was done.
