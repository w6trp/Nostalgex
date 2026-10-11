# Personal fork configuration

No telemetry or shared metadata writes are enabled by default. No credentials are included.

- TelemetryDeck: set your own TelemetryDeckAppID Info.plist value or TELEMETRYDECK_APP_ID environment variable explicitly. The upstream app identifier was removed from the plist and launch schemes.
- Metadata: TMDB_API_KEY and optional OMDB_API_KEY enable direct lookups. Metadata is cached locally by media type and TMDB ID; Supabase is no longer required.
- Optional remote cache: only after provisioning a fork-owned table, set SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_ENRICHMENT_V2_TABLE (or the corresponding Info.plist keys). The table must have a composite primary/unique key on (media_type, tmdb_id), with the columns documented by Models/MediaEnrichment.swift. Do not point the v2 setting at the old single-ID table. Create the table separately, review row-level security and write validation for the intended users, then enable it. No table creation, migration, policy change or live write was performed for this change. Leaving the table name blank disables both reads and writes.
- Apple signing: original bundle identifiers and App Group remain until the owner chooses the product identity and signing team. Both app and Top Shelf extension must share the configured group. No Apple agreement accepted.
- Top Shelf: artwork downloads use the selected media item's server. The shared snapshot contains local cached artwork paths; server URLs/tokens stay in memory. Disconnect cancels in-flight downloads and clears shared artwork and titles. Future cards can be text-only until their artwork is cached. Deep links are registered as nostalgex://channel/<id>; choose a fork-specific scheme alongside the final branding.

Hosted Xcode 26.6 compilation and NostalgexTests passed on the reliability branch. Signed device playback and UI validation remain necessary before distribution; simulator tests do not establish signing, Top Shelf file-image rendering or remote-control focus on hardware.
