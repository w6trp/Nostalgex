# Plex live activity without watch-history changes

## Build 47 experiment authorization

The owner explicitly authorized using the existing signed-in profile after being told persistence effects were unverified. The earlier disposable-profile proposal below is retained as the original protocol, not a current blocker. No new Plex account/token or permissions are authorized or needed.

Build 47 adds a distinct experimental heartbeat toggle with no position/duration fields and no scrobble. Its guarded reporter captures stored state before writing, compares every sampled item on later requests and periodic reads, observes the exact app client in current sessions, and turns the toggle off on any changed field/history digest or incomplete verification. The app uses its existing login. History filtering is by sampled item; an administrator may see other profiles' history for that item, so another viewer can cause a conservative stop. Stored metadata fields still use the signed-in profile. Maximum ten minutes/twelve items. It never resets state. The app-local `Documents/couchwave-heartbeat-audit.json` contains aliases, stored-state numbers/digests, session states and outcomes, not tokens, titles, server addresses or account identifiers. Read-only inspection failures are not treated as a pass.

The debug launch argument `-couchwaveHeartbeatOnly` enables the experiment only when an existing Plex login is present; `-couchwaveReportingOff` disables both modes. Ordinary installs remain default off. The Settings toggle also allows stopping the experiment. Code tests passed; real server behavior is not yet established.

## Current decision

Do not enable the installed History & Resume Sync switch for this requirement. In CouchWave 1.0.25 (46), source `f508c21`, that switch permits `POST /:/timeline` on playback-state changes and at ten-second intervals. It also permits `PUT /:/scrobble` when entry occurred in the first 15% and measured viewing reaches 75% of the item. Omitting scrobble is not a verified way to prevent timeline persistence.

The [official Plex Media Server API](https://developer.plex.tv/pms/#tag/Timeline) checked on 2026-10-11 documents timeline state, playback position, duration and session identity. Its published timeline parameters do not include a history-suppression option. `continuing` describes transition to another item; `offline` describes synchronization of offline playback. Neither is documented as a privacy mode. This is an evidence gap, not proof that every Plex implementation makes separation impossible.

No live reporting writes or watch-state experiment were performed. No disposable profile or test token has been verified as authorized. The app's existing default remains off. App installation and synthetic tests cannot establish Plex server persistence behavior.

## Bunny Ears TV lead

The developer's [playback feature page](https://www.bunnyearstv.com/features/playback-streaming) links an [official settings screenshot](https://www.bunnyearstv.com/images/features/screenshots/iphone-playback-settings.jpeg) showing **Plex Tracking: Heartbeat Only**. Its description says the app indicates active viewing without transmitting playhead position, to prevent idle-session termination. This supports investigating a heartbeat mode. It does not publish the endpoint/payload or demonstrate unchanged persisted history, last-viewed time or resume state.

A concrete candidate is `POST /:/timeline` with item key/rating key and actual state, plus the usual authenticated client/session headers, but with `time` and `duration` omitted and the scrobble path disabled. The official schema does not mark the time/duration query parameters required. Omitting optional position is different from sending a fabricated zero. This is a test hypothesis, not a claim about Bunny Ears' private implementation or Plex's persistence semantics. No undocumented ignore flag has been verified. Session identifiers distinguish playback instances and play queues identify scheduled items; neither documented role promises history suppression.

The earlier absence of an explicit no-history parameter should not be read as proof the desired behavior is impossible. The practical next step is this scoped position-free experiment, rather than enabling the installed full-history switch. Bunny Ears' separate local resume setting also must not be confused with Plex account resume state.

## Isolation required before any reporting experiment

Use an existing, explicitly authorized disposable Plex profile and two approved sample titles. Verify the profile identity in Plex and that its token actually belongs to that profile before collecting metadata: item watch fields are user-specific. Confirm the selected titles have no personal viewing state that needs preservation. Record the server version, client build and relevant watched/credits settings without changing the server settings. Ensure no other client uses the test profile during the experiment.

A separate existing administrator credential may be used only for authorized read-only session observation. The [Status API](https://developer.plex.tv/pms/#tag/Status) requires administrator access for the session list; playback history supports account and item filters. Do not confuse administrator-view metadata with the test profile's watch state. Confirm server account IDs and client identifiers locally, without publishing them.

If a disposable profile does not exist, obtain explicit approval to create a named test profile with access limited to a selected sample library, and to authorize its test login. That approval has not been assumed or obtained. Do not create a token, account, library, public share or new persistent access in preparation. Do not delete, unwatch or restore real history afterward.

## Prepared observer

`scripts/plex-history-observer.py` uses only allowlisted GET endpoints. It never starts playback, reports a timeline, scrobbles, deletes history, refreshes metadata, creates accounts or changes preferences. It requires direct HTTPS, keeps certificate validation, rejects redirects, accepts tokens only through hidden local prompts and never prints response bodies, titles, addresses or tokens. Use the existing approved secret handoff locally; never paste a token into chat or a command argument.

It reads user-scoped item metadata, fully paginated account/item history, and current sessions. Output labels items by ordinal and includes only the three watch-state fields, a history count/digest and matching session state/position. Session filtering requires account, item and exact client identity. Incomplete pagination, permission failures or mismatched scope make the result inconclusive. History digests are comparisons, not anonymized data intended for publication; keep complete observation files outside this public repository.

Example with placeholders only:

```sh
python3 -B scripts/plex-history-observer.py \
  --server https://APPROVED-DIRECT-SERVER:32400 \
  --account-id TEST_PROFILE_ID \
  --client-id TEST_APP_CLIENT_ID \
  --rating-key SAMPLE_A_ID --rating-key SAMPLE_B_ID
```

After the baseline, press Enter at each checkpoint; `q` finishes. The observer exits with a failure status if any stored watch field or history fingerprint changes. A network or access error must never be treated as zero history or no active sessions. Concurrent changing history can make pagination inconclusive, so use an idle isolated profile and recheck after it settles.

Synthetic validation: `python3 -B scripts/plex-history-observer-test.py` passes seven tests covering blocked write endpoints, origin validation, redirect rejection, session isolation, privacy filtering, history changes, incomplete reads and watch-field changes independent of a live session position. No test connects to a server.

## Experiment sequence after explicit isolation approval

1. **Control, reporting off.** Baseline both samples; play A, pause/resume, switch to B, and stop using CouchWave. Observe whether media requests alone produce live sessions. This may already reveal some server visibility without adding reporting writes; no claim is made that it will.
2. **Position-free heartbeat research build, disposable profile only.** If the control is insufficient, prepare a separate explicit test mode that suppresses scrobble, omits time/duration and reports only the selected item and actual playback state with client/session identity. Label it as an experiment that may change history/resume, not as private activity mode. Bind the experiment to the approved profile and sample IDs, and refuse other identities. Do not enable the existing full history switch on the owner's profile. This research mode is not implemented or installed yet.
3. **Checkpoint matrix.** Capture before start, once playback begins, after 15 and 60 seconds, while paused, after resume, after each rapid channel change, on stop, and 30 seconds and five minutes after stop. Compare `viewCount`, `viewOffset`, `lastViewedAt` and history for BOTH samples at EVERY checkpoint. In parallel confirm the matching session identifies the current item and correct playing/paused state, then disappears after stop.
4. **Edge cases.** With synthetic samples in the disposable profile, cover mid-program entry, entry near the end, natural completion, seeking, buffering, app backgrounding/relaunch and abrupt termination. Test direct play and a supported transcode separately. Do not stop or restart the production Plex server for this experiment.
5. **Persistence check.** After the app is closed, reload the scoped metadata/history and inspect the test profile's Continue Watching and history in a separate Plex client. Recheck after normal server persistence has settled. A server-local result alone cannot establish absence of account/cloud history or third-party logging; inspect those separately only within authorized access.

A pass requires observed live visibility with accurate item/state AND all stored watch fields/history unchanged throughout and afterward. A single changed value fails the no-history claim even if the title is not visibly marked watched. Stop further test writes on failure; preserve sanitized failure evidence. Do not falsify playback time, report fabricated durations or clean up history to disguise effects.

Any passing result is limited to the tested server version, configuration and playback paths. A production live-only flag should be separate from History & Resume Sync, off by default, and not offered until its mechanism and failure behavior are substantiated. Updating Plex requires revalidation. If Plex has no supported separation, a dedicated profile can protect the owner's personal history but may retain its own history; that is a different product option, not a zero-history solution.
