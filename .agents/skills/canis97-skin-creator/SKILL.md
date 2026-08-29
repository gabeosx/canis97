---
name: canis97-skin-creator
description: Create, edit, package, or troubleshoot safe declarative .canis97skin appearances for Canis97. Use when a user wants a new Canis97 theme, palette, fixed expressive layout, faceplate, or importable skin archive; do not use for changing player behavior or application code.
---

# Canis97 Skin Creator

Create an importable skin that preserves Canis97’s controls, accessibility, and security boundaries.

## Read the format before writing

- In a Canis97 checkout, read `docs/skins/creating-a-skin.md` and inspect the closest bundled manifest under `SiriusMac/Skins/Bundled/`.
- When this skill is installed standalone, read [references/skin-format.md](references/skin-format.md).

Do not infer new manifest keys from a visual request. The decoder rejects unknown keys.

## Choose the narrowest schema

- Prefer schema 2 for colors, spacing, corner radius, and optional background or metadata-panel images.
- Use schema 3 only when the request needs an app-owned expressive layout, typography tokens, semantic slot geometry, or decorative faceplate assets.
- Never add scripts, fonts, audio, remote URLs, HTML/CSS, arbitrary controls, window behavior, or playback behavior to a skin.

## Workflow

1. Turn the visual request into a short direction: palette, contrast, foreground scheme, density, shape, and optional local artwork.
2. Create a clean source directory with `manifest.json` at its root.
3. Use an identifier owned by the creator. Keep it stable across updates to the same skin.
4. For schema 2, write the exact required keys and use only `#RRGGBB` colors and in-range metrics.
5. For schema 3, start from the closest bundled layout. Preserve the required layout/silhouette/size tuple and all eight semantic slots; adjust geometry only within the documented grid, clearance, size, and non-overlap rules.
6. Add only assets named by the manifest. Prefer purpose-sized PNGs with enough contrast behind live artwork and metadata.
7. Package with `scripts/package_skin.sh <source-directory> [output.canis97skin]`.
8. If a Canis97 checkout is available, run focused skin validation or import tests without launching the app. Launch and visually inspect only when the user requests it and the environment’s app-run safety rules permit it.

## Review before delivery

- Confirm the archive root contains `manifest.json`, not a wrapper directory.
- Confirm every asset is referenced and no extra file is present.
- Check long channel/program/artist strings, light and dark artwork, paused/playing state, keyboard focus, and increased text size when visual testing is authorized.
- Report the schema, identifier, output path, referenced assets, and import steps.
- If the requested design cannot fit a supported layout or safe asset model, explain the exact constraint instead of weakening validation or editing app code.
