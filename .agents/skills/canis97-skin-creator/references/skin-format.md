# Canis97 skin format reference

Use this reference when creating or debugging an importable `.canis97skin` package. The current implementation accepts schema versions 1–3; create new work with version 2 or 3.

Validate either a clean source directory or a finished archive with:

```sh
./scripts/validate_skin.py ./my-skin
./scripts/validate_skin.py ./my-skin.canis97skin
```

The validator is bundled with the skill and uses the Python standard library plus macOS's built-in `sips`/ImageIO decoder. This final decode check matches the image stack used by Canis97 and rejects corrupt image payloads that merely have plausible headers. The packaging helper runs validation before and after creating the archive.

## Package envelope

- ZIP archive renamed with the `.canis97skin` extension.
- `manifest.json` must be at the archive root.
- Only `manifest.json` and the local assets it references may be present.
- Assets: single-frame PNG or JPEG, matching the filename extension, at most 4096×4096, 16,777,216 pixels, and 8 MiB per file.
- Limits: 16 MiB archive, 64 MiB expanded, 128 entries, 8 MiB per file, 64 KiB manifest, four path components, and 240 UTF-8 bytes per path.
- Encrypted entries, symbolic links, unsafe/colliding paths, extra files, and compression ratios over 100:1 are rejected.
- Animated GIF, APNG, animated WebP, video, and audio are not accepted assets. The current schemas have no animation or playback-triggered decoration keys.

Identifiers are ASCII, at most 64 bytes, start with a letter or number, and then contain only letters, numbers, `.`, `_`, or `-`. Display names are 1–64 characters with no surrounding whitespace. Colors are exactly `#RRGGBB`.

## Schema 2

Required keys are `schemaVersion`, `identifier`, `displayName`, `playerBackground`, `metadataPanel`, `accent`, `destructive`, `chromeHighlight`, `displayGlow`, `foregroundScheme`, `contentPadding`, `sectionSpacing`, and `cornerRadius`. Optional keys are `backgroundAsset` and `metadataPanelAsset`. No other key is accepted.

```json
{
  "schemaVersion": 2,
  "identifier": "com.example.midnight-radio",
  "displayName": "Midnight Radio",
  "playerBackground": "#10131A",
  "metadataPanel": "#202737",
  "accent": "#79D6FF",
  "destructive": "#FF6B7A",
  "chromeHighlight": "#B8EAFF",
  "displayGlow": "#315A78",
  "foregroundScheme": "dark",
  "contentPadding": 16,
  "sectionSpacing": 8,
  "cornerRadius": 8,
  "backgroundAsset": null,
  "metadataPanelAsset": null
}
```

- `foregroundScheme`: `light` or `dark`.
- `contentPadding`: 12–20.
- `sectionSpacing`: 4–12.
- `cornerRadius`: 0–12.

## Schema 3

The exact top-level keys are `schemaVersion`, `identifier`, `displayName`, `playerBackground`, `metadataPanel`, `accent`, `destructive`, `foregroundScheme`, `layoutVariant`, `silhouette`, `size`, `typography`, `slots`, `dragRegions`, and `decorations`.

Supported layout tuples:

| `layoutVariant` | `silhouette` | `size` |
|---|---|---|
| `legacyStack` | `nativeRect` | `legacy400x288` |
| `desktopUtility` | `pixelNotched` | `desktop432x304` |
| `discConsole` | `discPod` | `console384x320` |
| `aquaPod` | `bubbleCapsule` | `capsule448x304` |

Typography roles `display`, `body`, and `label` each use `systemDefault`, `systemRounded`, or `systemMonospaced`.

Define exactly one frame for each slot: `artwork`, `channelIdentity`, `metadata`, `favorite`, `status`, `transport`, `library`, and `overflowMenu`.

- All x/y/width/height values are nonnegative multiples of four.
- Frames stay within the canvas with four points of focus clearance and do not overlap.
- Interactive frames (`favorite`, `transport`, `library`, `overflowMenu`) are at least 32×32.
- `channelIdentity` is at least 96×20; `metadata` 128×40; `status` 80×20.
- At least one drag region is required. Each is at least 80×20 and cannot overlap a slot.
- Decorations allow `backdrop`, `chromeFrame`, `displayPlate`, and up to three `ornaments`. Across all decoration paths, at most six unique canonical local paths are allowed.
- Design artwork around the real renderer, not only these minimums. The idle status sentence is much longer than `Playing`, `Paused`, or `Stopped`; give it enough quiet visual space or accept intentional truncation with a full accessibility value.
- Decorative assets render behind app-owned semantic content. Do not paint labels, transport symbols, focus rings, or other clickable-looking UI into the faceplate.

Use the current bundled [Pixel Desk](https://github.com/gabeosx/canis97/blob/main/SiriusMac/Skins/Bundled/PixelDesk.json), [Pocket Disc](https://github.com/gabeosx/canis97/blob/main/SiriusMac/Skins/Bundled/PocketDisc.json), or [Aqua Vista](https://github.com/gabeosx/canis97/blob/main/SiriusMac/Skins/Bundled/AquaVista.json) manifest as the base for schema 3.

## Import

In Canis97, open **Settings**, choose **Select Appearance**, and select the package. Native remains the recovery appearance if validation or rendering fails.

## Animation status and safe future direction

Animation is intentionally unsupported in schemas 1–3. Do not emulate it with multi-frame images, video, scripts, or remote content.

A future schema can preserve the declarative safety boundary by exposing a small app-owned motion vocabulary rather than arbitrary timelines. For a cassette deck, the preferred model is two static reel assets plus bounded geometry and a finite `rotateWhilePlaying` preset. Canis97 would own playback-state observation, pausing, frame scheduling, compositing order, and Reduce Motion behavior. Such a schema should:

- be a new version so schemas 1–3 remain byte-for-byte compatible;
- allow only named motion presets and local single-frame image assets;
- bind triggers to app-owned states such as `playing`, never user code or expressions;
- cap animated elements, dimensions, update rate, and duration/speed ranges;
- keep motion behind semantic controls and outside hit testing;
- pause when playback pauses/stops, the window is hidden, or the app is inactive;
- render a meaningful static state when Reduce Motion is enabled;
- reject unknown presets, properties, assets, and out-of-bounds geometry.
