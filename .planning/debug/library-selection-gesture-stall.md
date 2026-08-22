---
status: diagnosed
phase: 03-native-mac-listening-experience
gap_id: G-03-7
diagnosed: 2026-08-22T15:41:30Z
---

# Library Selection Gesture Stall

## Symptom

Single-clicking another station does not promptly move the native selection highlight, and the library briefly appears to hang.

## Root Cause

Each selectable native `List` row also installs `.onTapGesture(count: 2)` for tuning. SwiftUI's double-click recognizer competes with the list's native single-click selection and waits through the double-click interval before resolving the click. This breaks the required immediate single-click browse-selection behavior and produces the observed stall.

## Evidence

- `SiriusMac/Catalog/ListeningView.swift` binds the `List` selection to `model.selectedChannelID` and tags each row correctly.
- The same row installs `.onTapGesture(count: 2)` directly after `.contentShape(Rectangle())`.
- The model's `select` method is a synchronous assignment, so no catalog, persistence, or playback work explains the delay.
- Existing `LibraryViewStateContractTests` cover tab/search values only; the project has no XCUITest target exercising actual native row selection or double-click activation.

## Fix Direction

Move double-click activation behind an AppKit-compatible list-row double-action mechanism that does not delay native selection, or otherwise separate selection and activation recognizers. Add XCUITest coverage proving immediate single-click highlight movement without tuning and exactly-one tune on double-click/Return.
