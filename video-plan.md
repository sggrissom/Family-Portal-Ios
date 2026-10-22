# Video (iOS)

The app's side of video. The design, the upload lifecycle and the playback
contract are in `Family-Portal/docs/plans/video.md` and
`Family-Portal/docs/mobile-api.md` (§ Video upload, Video playback, Saving
every original). This file only covers what differs on iOS. The web client
(`VideoPlayer.tsx`, `videoUpload.ts`, `videoFiles.ts`, `videoPlayback.ts`) is
the behaviour reference.

## What the server changed under the app

A video is an `Image` with `mediaKind: 1`. It arrives through the same
`ListFamilyPhotos` and `GetFamilyTimeline` the mirror already pulls, so an
unchanged build already shows every video — as a still. Its variants
(`/api/photo/<id>/thumb` …) are the poster frame, `original` is a 404, and
while it processes the variants are the SVG placeholder `PhotoImageCache`
already reads as `.processing`. What an unchanged build gets wrong:

- nothing says it is a video, and the photo page can't play it;
- **Share original / Save to Photos** fail (404);
- **Use as Profile Photo** offers it, and the server refuses it.

New fields on `Image`: `mediaKind`, `durationMs`, `videoCodec`,
`audioCodec`, `processingError` (all `omitempty` except `mediaKind`, so all
decode leniently). `status` (0 ready, 1 processing, 2 failed) was already on
the wire and is now worth keeping.

## Model

`Photo` gains `mediaKind: MediaKind = .photo`, `durationMs = 0`,
`status = 0`, `processingError = ""`. Defaults on every new property, so the
store migrates lightweight and old rows read as ready photos. A kind this
build doesn't know reads as a photo. Codecs are not stored: only playback
needs them, and `GetVideoPlayback` returns them as `mimeType`.

`Photo` stays the name. A video is a second kind of the same record, as on the
server; renaming the model would touch every file for nothing.

## Where a video appears, and where it doesn't

As on the web, a video sits beside photos everywhere media is listed —
gallery, person Photos tab, History days, search, milestone and activity
pickers — as its poster with a play badge (`play.fill` + `m:ss`, from
`durationMs`). The badge lives in `PhotoThumbnailView`, so every grid gets it.
Cells that only know a server id (a place or search result the mirror doesn't
hold yet) show no badge until the mirror catches up.

Kept out, like the web: the profile-photo picker and **Use as Profile Photo**
(the server refuses it). Same age, Growing up, books and face review are fed
by server procs that already filter videos. Widgets keep videos, which are
just a poster there, but skip anything not ready (a processing poster is an
SVG).

## Playback

`GetVideoPlayback {id}` on opening a video's page, online only, never cached
or stored — the links expire. `AVPlayerViewController` (system controls, PiP,
AirPlay, full screen) over an `AVURLAsset` with **no cookies and no bearer
token**: `AVURLAssetHTTPCookiesKey: []`, since the app keeps its auth cookies
in the shared jar and the contract says the URL carries its own authority.
A relative `playbackUrl` resolves against the API base URL.

States, matching the web player:
- **Processing** (`status 1`): the poster and "Still processing". The page
  asks `GetVideoPlayback` again every few seconds while it is on screen.
- **Failed** (`status 2`): the poster, `processingError` as is, and the
  original's actions if `downloadUrl` is present.
- **Ready**: the player. iOS plays H.264 and HEVC, so there is no
  `canPlayType` gate. A player failure is classified like the web's
  `classifyPlaybackError` (ported, with its test table): past or within a
  minute of `expiresAt`, or a 400/401/403 from a one-byte range probe of the
  link → renew through `GetVideoPlayback` and resume at the same position (at
  most three times); a probe that answers 2xx → "can't be played on this
  device" with the original's actions; anything else → "Playback stopped"
  with Try again.
- **Offline**: the poster and a line saying video needs a connection.

**Share original / Save to Photos** for a video use `downloadUrl` instead of
`/api/photo/<id>/original`, downloaded without credentials, named
`originalFilename`, and saved as a `.video` asset.

## Upload

The **+** picker matches `.any(of: [.images, .videos])` when
`GetVideoSupport` says video is on for the acting family, and `.images`
otherwise. Support is asked when the add sheet opens, online, and not
remembered across launches — it is an admin switch.

Videos upload **online only, and are not queued**. Everything else the app
adds is local-first, but the contract doesn't fit the queue: `BeginVideoUpload`
reserves quota and hands out a URL that dies in two hours, and a queued
gigabyte in SwiftData is the wrong place for it. A video picked offline is
refused with a sentence saying so.

The flow rides `PhotoImporter`, so one progress bar and one batch form cover a
mixed pick:
1. Load the item as a file (`Transferable` `FileRepresentation`, copied to a
   scratch folder). Refuse over `maxBytes`, a type that isn't MP4/MOV/M4V,
   and a duration (`AVURLAsset.load(.duration)`) over `maxDurationSeconds`,
   with the web's wording.
2. `BeginVideoUpload` with no people (the batch form asks who's in it
   afterwards, as for photos), `fallbackDate` = the library's capture day,
   else today.
3. Send the file with an upload task from the file, using exactly `method`
   and `headers`, on a session with no cookies and no token. Progress is the
   entry's.
4. `CompleteVideoUpload`, retried up to four times with backoff, except on
   `ErrVideoUploadExpired` / not found. On a failed send, `CancelVideoUpload`.
5. Insert the returned image as a `Photo` with its server id. The batch
   form's choices then queue against a photo that already has a server id —
   no new path.

`beginBackgroundTask` covers a short trip out of the app. A background
`URLSession` that survives the app being killed is a later addition if the
family finds uploads dying.

## Plumbing

- `RPCMethod`: `getVideoSupport`, `beginVideoUpload`,
  `completeVideoUpload`, `cancelVideoUpload`, `getVideoPlayback`. Not the
  admin procs or the bulk originals export: those stay on the web.
- `VideoDTOs.swift` for the requests and responses; `ImageDTO` gains the new
  fields.
- `Copy.video` for wording shared with the web.
- `VideoDuration.format` is a port of `formatDuration` in `videoFiles.ts`.

## Phases (stacked PRs)

1. **Model, badges and originals.** DTO fields, `Photo` fields and mapping,
   the RPC names and DTOs, `VideoDuration`, the badge, the profile-photo
   exclusions, widgets skipping unready videos, and the original's
   share/save through `downloadUrl`. Tests: decoding with and without the new
   fields, mapping, duration formatting, media links resolved and fetched
   without credentials.
2. **Playback.** `VideoPlayerSection` on the photo page with the four states,
   renewal and resume, and `PlaybackProblem` classification (pure, tested).
3. **Upload.** Video support on the add sheet, `VideoUpload` (checks, begin,
   send, complete with retries, cancel), the importer branch and per-entry
   progress in the batch form. Tests: the file checks and the completion
   retry policy against `FakeHTTP`.
