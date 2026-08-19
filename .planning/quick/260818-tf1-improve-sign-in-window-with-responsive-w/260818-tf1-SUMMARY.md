---
quick_id: 260818-tf1
status: complete
description: Improve sign-in window with responsive WebView sizing and subtler border
code_commit: e469deb
completed: 2026-08-18
---

# Responsive sign-in window summary

- Removed the 520-point cap from the active sign-in flow and allowed the WebView to use up to 1200 points of content width plus the available height.
- Replaced the heavy default GroupBox with one rounded 1-point separator stroke at 20% opacity.
- Added a 1160×820 default window size with a navigable 760×620 minimum while preserving resizing.
- Verified the built app visually at default and reduced sizes without loading SiriusXM or clicking an authentication action.
- `./script/build_and_run.sh --build-only` succeeded.
- All 46 SiriusMac tests passed.

The separate visual-check window was closed after inspection; any pre-existing app/session was not intentionally closed or cleared.
