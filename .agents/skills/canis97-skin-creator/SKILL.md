---
name: canis97-skin-creator
description: Create, edit, package, or troubleshoot safe declarative .canis97skin appearances for Canis97. Use when a user wants a new Canis97 theme, palette, fixed expressive layout, faceplate, or importable skin archive; do not use for changing player behavior or application code.
metadata:
  short-description: Create safe Canis97 skin packages
---

# Canis97 Skin Creator

Create an importable skin that preserves Canis97’s controls, accessibility, and security boundaries.

## Load only the format you need

- Always read [references/skin-format.md](references/skin-format.md) before authoring or troubleshooting a manifest.
- In a Canis97 checkout, also inspect the closest bundled manifest under `SiriusMac/Skins/Bundled/`. The checkout is useful for visual references, but is not required to validate or package a skin.

Do not infer new manifest keys from a visual request. The decoder rejects unknown keys.

## Choose the narrowest schema

- Prefer schema 2 for colors, spacing, corner radius, and optional background or metadata-panel images.
- Use schema 3 only when the request needs an app-owned expressive layout, typography tokens, semantic slot geometry, or decorative faceplate assets.
- Current schemas do not support animated assets or playback-triggered decoration. Never invent animation keys or use GIF/APNG/video as a workaround.
- Never add scripts, fonts, audio, remote URLs, HTML/CSS, arbitrary controls, window behavior, or playback behavior to a skin.

## Workflow

1. Turn the visual request into a short direction: palette, contrast, foreground scheme, density, shape, and optional local artwork.
2. Create a clean source directory with `manifest.json` at its root.
3. Use an identifier owned by the creator. Keep it stable across updates to the same skin.
4. For schema 2, write the exact required keys and use only `#RRGGBB` colors and in-range metrics.
5. For schema 3, start from the closest bundled layout. Preserve the required layout/silhouette/size tuple and all eight semantic slots; adjust geometry only within the documented grid, clearance, size, and non-overlap rules. Treat the full idle status message as a real text case, not just the shorter Playing/Paused labels.
6. Add only assets named by the manifest. Prefer purpose-sized PNGs with quiet regions behind live artwork and text and visibly distinct wells behind native controls. Generated faceplates should omit text, logos, and clickable-looking controls.
7. On macOS, validate the source with `scripts/validate_skin.py <source-directory>`. The helper uses built-in ImageIO through `sips` for a full asset decode. Fix validation errors rather than weakening the manifest or validator.
8. Package with `scripts/package_skin.sh <source-directory> [output.canis97skin]`. The helper validates both the source and final archive and refuses to overwrite an existing package.
9. Launch and visually inspect only when the user requests it and the environment’s app-run safety rules permit it. Import through Canis97 instead of copying files into its managed package store.

## Review before delivery

- Run `scripts/validate_skin.py <output.canis97skin>` even when another tool created the ZIP.
- For expressive faceplates, compare the artwork’s quiet regions with every semantic slot before import. Static geometry passing does not prove text will remain readable.
- When visual testing is authorized, check empty/idle, long channel/program/artist strings, light and dark artwork, paused/playing state, keyboard focus, reduced motion, and increased text size. Confirm Native recovery and reselect the skin afterward.
- Report the schema, identifier, output path, referenced assets, and import steps.
- State clearly when app import, playback-state rendering, focus, reduced-motion, or increased-text checks were not run.
- If the requested design cannot fit a supported layout or safe asset model, explain the exact constraint instead of weakening validation or editing app code.
