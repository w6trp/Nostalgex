# Nostalgex Devtools

Local web UIs for validating the Nostalgex channel rotation and Plex library health. **Local only — never deployed, never shipped in the app.**

## What's in here

- **Schedule Explorer** (`/schedule.html`) — search every airing across all channels for the past 7 days through next 7 days. Validates that titles you expect to see in rotation actually are, and confirms the deterministic algorithm puts them where you expect.
- **Channel Pools** (`/pools.html`) — pick a channel, see exactly which titles are eligible plus the filter rules side-by-side. Decade/genre/type breakdowns make rule mistakes obvious at a glance.
- **Library Audit** (`/audit.html`) — scans every movie / episode in your Plex library and flags files most likely to cause tvOS playback issues (no audio, lossless audio AVPlayer can't decode, MKV containers, HEVC 10-bit, AV1, wrong default language, very high bitrate).
- **Channel Memberships** (`/memberships.html`) — inspect the TMDB membership manifest: which titles are claimed for which channels, by exemplar or by TMDB's recommendation graph.
- **Channel Coverage** (`/coverage.html`) — every item in the library and how many channels pull it in. Finds orphans (items in zero channels), groups them by the most likely reason, flags channels below their `minItems`, and answers "where is X?" for any title. See *How coverage works* below before trusting the numbers.

## Run it

Put credentials in `.env` at the **repo root** (gitignored, set once):

```
PLEX_URL=https://your-plex.example.com:32400
PLEX_TOKEN=your-plex-token
TMDB_API_KEY=your-tmdb-key
```

Then, from the repo root:

```bash
npm run snapshot        # build scripts/devtools/snapshot.json from Plex (+ TMDB keywords for movies)
npm run devtools        # start the server → http://localhost:3030
npm run devtools:full   # both
```

The npm scripts load `.env` via `node --env-file-if-exists`; nothing in the devtools reads `.env` on its own, so running `node server.mjs` directly needs the variables exported in your shell.

Schedule, Pools and Coverage read the snapshot. Only Library Audit needs a live Plex connection. Rebuild the snapshot after a library change or a rule change; it does not refresh itself.

**The CLEAR button in the snapshot bar deletes `snapshot.json`.** It cannot be undone, and there is no fallback unless Plex credentials are set. Rebuild with `npm run snapshot`.

Optional: `PORT=8080 npm run devtools` to bind a different port.

## How to find your Plex token

Plex Web → any item → ⋯ → **Get Info** → **View XML** → the `X-Plex-Token=…` query param in the URL bar is your token.

## Access and transport

The server binds to `127.0.0.1` by default. LAN access is opt-in: set
`DEVTOOLS_HOST` and a separately supplied `DEVTOOLS_TOKEN` of at least 32 characters.
API clients send `Authorization: Bearer <token>`; the browser uses its Basic-auth
prompt (any username, token as password). Tokens are never accepted in URLs.
Use only a trusted network or an authenticated TLS reverse proxy for LAN access;
the built-in HTTP listener does not encrypt transport. Never expose this diagnostic
server to the public internet. Requests from other browser origins are rejected.

Plex HTTPS uses normal certificate validation. Configure `NODE_EXTRA_CA_CERTS`
with a trusted private CA when necessary. Do not disable TLS validation globally.

## Schedules and coverage

Generated schedules use `scripts/nostalgex-daily-manifest.js`, the same packing
engine as the browser tuner, including local calendar day boundaries and partial
source offsets. A generated snapshot begins without the device's previous-day
manifest cache. Pool contents, enrichment, local timezone and prior manifest state
can still differ from an Apple TV. Use a snapshot exported by that device to inspect
what it actually scheduled. Generated snapshots are diagnostic reconstructions.

The shared channel filter implements rating, keyword and network rules. Plex supplies
ordinary ratings/genres; optional TMDB enrichment fetches keywords for both films and
shows. Missing TMDB/OMDb/network/company data can reduce or otherwise change channel
membership. Coverage reports list candidates to investigate, not proven library
problems or exact parity guarantees. Snapshot data does not refresh itself.

## How the audit works

The audit hits the Plex API directly, walks every section, fetches detailed Media/Part/Stream metadata for each item, and runs the rule set in `lib/audit.mjs`. Same rules as the original CLI version, just exposed via HTTP.

| Tag | Severity | What it means |
|---|---|---|
| `no-audio-track` | high | File is missing an audio stream entirely |
| `lossless-audio:*` | high | TrueHD / DTS-HD MA / Atmos — AVPlayer can't decode natively, audio may drop |
| `container-mkv` | medium | MKV forces remux/transcode wrap on tvOS — slow start |
| `hevc-10bit` | medium | HEVC 10-bit can stutter on older Apple TVs, HDR may force transcode |
| `av1-codec` | medium | AV1 not hardware-decoded on most Apple TV generations |
| `default-audio:*` | low | Default audio track is non-English — viewer may hear the wrong language |
| `very-high-bitrate` | low | >60 Mbps — may stutter on limited bandwidth |

### Fixing flagged files

- **TrueHD / DTS-HD MA**: re-encode the audio track to AC3 or AAC. HandBrake preset "Apple TV 4K" → Audio tab → Codec: AC3 Passthru with AAC fallback.
- **MKV containers**: remux to MP4 with `ffmpeg -i in.mkv -c copy out.mp4` (no re-encode needed).
- **HEVC 10-bit stutter**: usually fine on Apple TV 4K (2nd gen+); flag is informational. Re-encode to 8-bit H.264 if targeting older devices.
- **Wrong default audio**: in Plex Web → episode/movie → Audio & Subtitles → "Set Audio as Default" for the English track.

## Architecture

```
server.mjs           # zero-framework Node http server, static + JSON API
build-snapshot.mjs   # Plex → snapshot.json (pools + schedules for every channel)
lib/
  plex.mjs           # Plex API wrapper
  tmdb.mjs           # TMDB keyword enrichment (movies), cached on disk
  schedule.mjs       # JS port of the schedule algorithm
  channels.mjs       # channels.json loader + pool filter (shared with plex-tuner.html)
  memberships.mjs    # channels-memberships.json + exemplars.json readers
  snapshot.mjs       # snapshot store (in-memory + snapshot.json on disk)
  coverage.mjs       # item → channels inversion, orphan reasons, thin channels
  audit.mjs          # audit rules + scan runner
public/
  index.html         # landing
  schedule.html      # schedule explorer
  pools.html         # channel pool inspector
  memberships.html   # manifest inspector
  coverage.html      # channel coverage
  audit.html         # library audit
  snapshot-bar.js    # shared snapshot status bar
  styles.css         # shared dark/cyan/mono styles
```

No build step. No dependencies. `npm run devtools`.
