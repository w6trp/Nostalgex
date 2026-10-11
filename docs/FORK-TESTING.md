# Fork testing and distribution

The native application is Swift/SwiftUI for tvOS, with an AVPlayer playback layer
and a Top Shelf extension. The browser tuner is a separate Vite application.
A browser build does not produce an Apple TV application. Preserve LICENSE and
upstream attribution when changing the product name or distributing a build.

## Current validation boundary

The CouchWave beta also passed local Xcode 27.0 device compilation and the tvOS 27 simulator suite (464 passed, 2 opt-in live harnesses skipped). The physical-device build is unsigned. Bundle identifiers and URL scheme were verified in the built product; signing and hardware playback remain unverified.

The reliability branch passed [hosted CI](https://github.com/w6trp/Nostalgex/actions/runs/38155433349) on source commit
`3cf55f1072c4ddf6e1e711b0507d0990411f1143`: Xcode 26.6 compiled the application
and completed NostalgexTests on an Apple TV simulator (464 passed, 2 opt-in live
harnesses skipped). Web checks and Vite build passed. This validates compilation
and the unit suite, not real media playback or signed installation. Local tests
and device work still require full Xcode; Command Line Tools alone are insufficient.

## Toolchain and storage

- Install Apple's Xcode 27 in /Applications for a device running tvOS 27. Select
  only tvOS components initially. Check Apple's system requirements for the exact
  host and device OS combination before upgrading.
- Keep source, DerivedData and archives on a local external development volume,
  outside synced document folders. Set Xcode Settings > Locations > Derived Data
  to that volume. Command-line builds can pass -derivedDataPath explicitly.
- Complete any Apple account sign-in, two-factor challenge and agreement review
  directly. No credentials or signing assets belong in this repository.
- The existing CI definition pins Xcode 26.6 on macos-26 for simulator tests of
  the tvOS 18 deployment target. This does not validate deployment to tvOS 27.
  Editing the workflow does not enable Actions in a fork or constitute a CI run.

Official references: [Xcode requirements](https://developer.apple.com/xcode/system-requirements)
and [run on a device or simulator](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## First local checks

From the repository root after installing Xcode and the tvOS simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Nostalgex/Nostalgex.xcodeproj \
  -scheme Nostalgex \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -only-testing:NostalgexTests \
  CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Choose an installed tvOS simulator if its name differs. Set a DerivedData location
on the development volume before a large build. Inspect package resolution and
any requested platform downloads; do not bypass signing or agreement errors.

The independent web checks are:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run build
```

## Direct installation for initial testing

1. Sign in to the intended Apple Account in Xcode. Xcode shows the available team
   and whether it is a Personal Team. An old email address alone cannot establish
   paid membership status; the developer account page shows current membership.
2. CouchWave uses app ID `io.github.w6trp.couchwave`, extension ID
   `io.github.w6trp.couchwave.TopShelf`, App Group `group.io.github.w6trp.couchwave`
   and URL scheme `couchwave`. Select the owner's signing team for both targets. Never use the upstream team
   or assume the upstream App Group can be provisioned by another account.
3. Pair the Apple TV in Xcode's device interface while the Mac and TV are on the
   same network. Complete the pairing code and device prompts on the TV. Network
   reachability alone does not mean it is paired or authorized for development.
4. Select the Nostalgex scheme and the paired Apple TV destination, then Build and
   Run. Retain the scheme name until a coordinated rename is reviewed. A distinct
   bundle ID lets the test fork coexist with the upstream installation.
5. Later updates use the same bundle ID/team and another Build and Run. There is
   no automatic update merely because code was pushed to GitHub.

Apple's free Personal Team profiles expire after seven days, requiring rebuild
and reinstall. Advanced capabilities have separate eligibility; validate App
Groups/Top Shelf provisioning before promising a complete free-team install.
If unavailable, choose explicitly between a separately configured core-app test
build without Top Shelf and the appropriate developer membership. Do not silently
strip capabilities or enroll in a paid program.

See [Apple account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

## TestFlight after initial hardware validation

TestFlight requires the owner's active developer-program/App Store Connect setup,
a fork-owned app record, reviewed identifiers and signing, and a new build number.
Archive, explicitly upload to the owner's record, wait for processing, then make
it available to the intended testers. External testing may require beta review.
Subsequent approved builds can be installed through TestFlight on Apple TV.
No upload, enrollment, agreement acceptance or review submission is implied by a
local code change. See [TestFlight](https://developer.apple.com/testflight/).

## Plex reporting and history

History and resume sync is off by default, including for an existing install that
previously enabled the ambiguous activity switch. The legacy preference remains
untouched for rollback. Enabling the new explicit setting permits timeline and
watched-state writes, which may affect history and Continue Watching.

The documented [Plex timeline API](https://developer.plex.tv/pms/#tag/Timeline)
does not expose a verified session-only, history-suppression mode. This fork does
not claim that omitting explicit scrobble makes timeline updates history-free.
With sync off the app does not send those reporting writes, but the server can
still observe media requests and transcode sessions. Live dashboard visibility
without any persisted watch/resume changes remains unverified and is not enabled.

Any future experiment needs an explicitly authorized disposable test profile and
sample item. Compare play count, last-viewed time, resume offset and history before
and after start, pause, seek, stop, completion and restart. Do not perform these
experiments on a real user's watch state, erase history or fake progress to hide
side effects.

## Device acceptance checks

- Tune rapidly, disconnect during resolution, sleep/wake, and switch servers while
  a library refresh is in flight. Old tasks must not alter the new session.
- Exercise direct play and fallback with supported H.264/HEVC samples, alternate
  versions, multipart media, audio languages and subtitles. Confirm fallback
  never raises a selected bandwidth ceiling.
- Check guide boundaries, overlapping content, midnight and daylight-saving days;
  a partial scheduled block must seek to its actual source offset.
- Confirm reporting stays off after upgrade unless explicitly opted in. Test any
  history-enabled reporting only against authorized disposable server data.
- Verify Top Shelf images, deep links and sign-out cleanup on physical hardware.
  A simulator does not establish the device's full decoder/capability behavior.

See [fork service configuration](../Nostalgex/docs/FORK-CONFIGURATION.md) for
telemetry and optional metadata-cache isolation.

## CouchWave beta identity

The internal project/scheme/module and app executable still use the upstream Nostalgex name. The installed display name is CouchWave, and its bundle ID, keychain service, App Group, links and media-server client names are independent. A code-rendered beta wordmark and icon replace upstream branding in the Apple TV UI. These identifiers are source configuration, not proof of Apple registration or successful signing. No domain has been registered.
