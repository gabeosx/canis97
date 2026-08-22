---
status: diagnosed
phase: 03-native-mac-listening-experience
gap_id: G-03-17
diagnosed: 2026-08-22T15:41:30Z
---

# Compact Window Excess Chrome

## Symptom

The fixed compact player opens inside a much larger window, leaving a large border around the 400 x 288 player canvas.

## Root Cause

`SiriusMacApp` creates the compact/authentication scene with a 760 x 620 default. After authentication, `CompactWindowController` installs a 400 x 288 minimum and maximum content size but accepts any on-screen autosaved frame unchanged. Setting `contentMaxSize` and removing `.resizable` do not shrink an already-large current/restored frame, so the former authentication-sized window remains around the fixed compact view.

## Evidence

- `SiriusMac/SiriusMacApp.swift` declares `.defaultSize(width: 760, height: 620)` for the compact/authentication scene.
- `SiriusMac/Player/CompactPlayerView.swift` fixes its canvas to the fallback style's 400 x 288 content size.
- `SiriusMac/Windows/CompactWindowController.swift` returns early after applying any intersecting saved frame and only calls `setContentSize(400 x 288)` when no saved frame is accepted.
- Existing unit tests validate policy constants, not the attached `NSWindow`'s resulting content frame.

## Fix Direction

For the compact role, restore only a valid origin and always enforce the exact 400 x 288 content size after attachment/authentication transition. Add an AppKit window test and a launched-app UI assertion for the resulting compact content frame.
