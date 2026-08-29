# Creating a Canis97 skin

A Canis97 skin is a ZIP archive with the extension `.canis97skin`. It contains one strict `manifest.json` and only the local PNG or JPEG files named by that manifest. Skins are declarative: they cannot execute code, load remote content, replace controls, or change playback behavior.

## Choose a format

- Use **schema 2** for a custom palette, spacing, corner radius, and optional panel images. This is the best starting point.
- Use **schema 3** when you want one of Canis97’s fixed expressive layouts, custom typography tokens, precise semantic slots, or decorative faceplate images.

The exact format limits are maintained with the installable skill in [skin-format.md](../../.agents/skills/canis97-skin-creator/references/skin-format.md).

## Five-minute schema 2 skin

Create a directory such as `midnight-radio` with this `manifest.json`:

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

The six colors must be `#RRGGBB`. `contentPadding` is 12–20, `sectionSpacing` is 4–12, and `cornerRadius` is 0–12. The display name must be 1–64 characters without leading or trailing whitespace.

Package it with the helper included in the repository skill:

```sh
./.agents/skills/canis97-skin-creator/scripts/package_skin.sh \
  ./midnight-radio \
  ./midnight-radio.canis97skin
```

The helper validates the JSON envelope, rejects hidden files and symbolic links, and creates a metadata-free ZIP without overwriting an existing package.

## Add local artwork

Schema 2 accepts `backgroundAsset` and `metadataPanelAsset`. Set either value to a relative PNG or JPEG path and put that exact file in the package:

```json
"backgroundAsset": "assets/background.png",
"metadataPanelAsset": "assets/display.jpg"
```

Only referenced files are allowed. Images must be single-frame PNG or JPEG files, at most 4096 pixels per side, at most 16,777,216 total pixels, and no larger than 8 MiB each. Paths are relative, case-sensitive package paths; do not use absolute paths, `..`, URLs, or symbolic links.

## Use an expressive schema 3 layout

Schema 3 keeps interaction and accessibility under Canis97’s control. Choose one matching layout tuple:

| Layout | Silhouette | Size |
|---|---|---|
| `legacyStack` | `nativeRect` | `legacy400x288` |
| `desktopUtility` | `pixelNotched` | `desktop432x304` |
| `discConsole` | `discPod` | `console384x320` |
| `aquaPod` | `bubbleCapsule` | `capsule448x304` |

Start from a bundled manifest instead of inventing the geometry from scratch:

- [Pixel Desk](../../SiriusMac/Skins/Bundled/PixelDesk.json)
- [Pocket Disc](../../SiriusMac/Skins/Bundled/PocketDisc.json)
- [Aqua Vista](../../SiriusMac/Skins/Bundled/AquaVista.json)

Every schema 3 package must define each semantic slot exactly once: `artwork`, `channelIdentity`, `metadata`, `favorite`, `status`, `transport`, `library`, and `overflowMenu`. Rectangles use a four-point grid, stay four points inside the selected canvas, and cannot overlap. Drag regions must be at least 80×20 points and cannot overlap a slot.

Typography is selected from `systemDefault`, `systemRounded`, and `systemMonospaced`. Decorations can name a backdrop, chrome frame, display plate, and up to three ornaments; all paths must be unique local assets referenced by the manifest.

## Import and test

1. Open **Canis97 → Settings**.
2. Choose **Select Appearance**.
3. Pick the `.canis97skin` file.
4. Confirm the compact player at long and short metadata lengths, light and dark artwork, paused and playing states, keyboard focus, and increased text size.
5. Keep the native appearance available as the recovery path.

If import fails, first check that `manifest.json` is at the archive root, the schema uses only its exact keys, every packaged asset is referenced, and no `.DS_Store`, hidden file, symbolic link, or extra preview image entered the archive.

## Package limits

The importer rejects archives over 16 MiB, expanded packages over 64 MiB, more than 128 entries, individual files over 8 MiB, manifests over 64 KiB, encrypted entries, symbolic links, unsafe paths, and excessive compression ratios. These are security boundaries, not tuning recommendations.

For agent-assisted creation, install and invoke [`$canis97-skin-creator`](../../.agents/skills/canis97-skin-creator/SKILL.md).
