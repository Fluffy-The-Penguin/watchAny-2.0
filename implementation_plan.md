# Support 1080p and 2160p (DASH) on Windows via On-The-Fly HLS Conversion

HStream's high-quality streams (1080p, 2160p) are served exclusively as MPEG-DASH (`.mpd`) manifests. Because the Windows video engine (`libmpv`) is built without `libxml2`, it natively lacks the capability to parse XML files and thus cannot play DASH streams, causing the app to crash.

## Proposed Changes

To bypass this limitation without modifying the native C++ video engine, we will build a dynamic DASH-to-HLS converter directly into our local Dart proxy server. 

### `lib/services/video_proxy_service.dart`
- **[MODIFY]** `_handleRequest`: Add routing for a new `/dash_proxy` endpoint.
- **[NEW]** Add an in-memory cache for `.mpd` manifest texts.
- **[NEW]** Add XML Regex parsing logic that:
  - Fetches the `.mpd` file from the CDN.
  - Converts the DASH `<SegmentTemplate>` and `<SegmentTimeline>` XML structures into an HLS `.m3u8` playlist format.
  - Generates a master `.m3u8` playlist pointing to separate video and audio playlists.
  - Rewrites all internal segment links (`chunks/chunk...`) to point back to our proxy server (`/dash_proxy?url=BASE&segment=...`).
- When the proxy receives a `segment` request, it securely forwards it to the CDN with the correct `Referer` and `User-Agent` headers.

### `lib/services/hstream_service.dart`
- **[MODIFY]** Remove the Desktop-specific filter that hides DASH streams. Desktop will now be allowed to see and select 1080p and 2160p qualities.

### `lib/state/player_state.dart`
- **[MODIFY]** Update the `proxyUrl` generation. If the stream is `.mpd` and the platform is Desktop, rewrite the URL to point to `/dash_proxy?url=...&type=master`. 

## Verification Plan

### Automated Tests
- `dart run test\dash_to_hls_test.dart` (Already run, confirmed regex logic generates flawless HLS syntax).

### Manual Verification
- Compile the Windows app.
- Attempt to switch the stream to 1080p.
- Verify that `media_kit` successfully loads the HLS master playlist, fetches the segments via the proxy, and plays the 1080p video with audio smoothly.
