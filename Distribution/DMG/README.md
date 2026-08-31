# Canis97 disk image

`background.png` is the approved 720 × 460 installer background built from the Exit97 road-trip artwork. `layout.applescript` applies the matching Finder window, icon sizes, and fixed Canis97 → Applications positions while the release image is writable.

The release workflow generates `.DS_Store` at package time. Do not check in a prototype `.DS_Store`: Finder background aliases contain machine-specific volume and source paths.
