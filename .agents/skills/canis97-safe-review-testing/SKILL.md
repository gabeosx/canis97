---
name: canis97-safe-review-testing
description: Safely build, test, launch, and manually review Canis97/Sirius Mac on the shared development Mac. Use this skill for SwiftPM validation, build-for-testing, playback or audio checks, UI review, remote review through Jump Desktop, crash recovery, and cleanup of test apps or build artifacts.
---

# Canis97 Safe Review Testing

Use one isolated compiler lane and one review app. Keep automated playback silent inside Canis97 so testing does not change the Mac's audio output or interfere with a remote desktop session.

## Start with recovery and scope

1. Read `/Users/gabe/sirius-mac/AGENTS.md` and any more specific nested instructions.
2. Inspect `git status` and the relevant diff. Treat every existing modification as user work unless the current session created it.
3. Check for surviving `Canis97`, `xcodebuild`, and `swift test` processes before starting another lane.
4. Inventory only task-owned temporary paths. Do not delete another session's cache or any repository file to reclaim space.
5. If a previous run crashed, verify source and process state before rebuilding. A crash alone does not justify repeating a successful full suite when its inputs are unchanged.

## Choose the narrowest allowed validation

Follow the repository safety block in `AGENTS.md`.

- Run `SiriusXMClient` package tests with `swift test` and a unique `mktemp -d` scratch path.
- Use `xcodebuild build-for-testing` to compile the app and test targets without launching either one.
- Do not run `xcodebuild test`, `test-without-building`, `xctest`, an app-hosted test, or a UI-test runner while the safety block remains active.
- Do not launch `script/build_and_run.sh` or `live_compatibility_checkpoint.sh` as a substitute for an allowed narrow check.
- Use synthetic fixtures and injected fake playback runtimes for automated logic tests. A `/dev/null` file URL is suitable only as inert fixture input; it is not a macOS audio output device.

Create a unique package scratch directory:

```bash
package_scratch="$(mktemp -d /private/tmp/canis97-swiftpm.XXXXXX)"
swift test \
  --package-path /Users/gabe/sirius-mac/Packages/SiriusXMClient \
  --scratch-path "$package_scratch"
```

Use a separate unique directory for every Xcode build-only lane. Keep DerivedData, cloned source packages, Clang modules, Swift modules, result bundles, and logs inside that directory. Allow at most one `xcodebuild` process at a time.

## Keep automated playback silent

Canis97 owns one production `AVPlayer`. Launch automated review builds with:

```bash
/usr/bin/open \
  --env CANIS97_MUTE_AUDIO=1 \
  /absolute/path/to/Canis97Review.app
```

`CANIS97_MUTE_AUDIO=1` sets `AVPlayer.isMuted` when the production playback runtime is created. XCTest hosts also default to this muted policy. This leaves the system volume, selected output device, Jump Desktop audio, and every other application unchanged.

Do not change system volume, mute the Mac globally, or switch its system output to a virtual device. Do not install an audio driver for routine review. Do not treat `/dev/null` as an AVFoundation output route.

## Launch exactly one review app

1. Quit the old review instance before launching a replacement.
2. Launch the exact app bundle path. Do not use `open -n`.
3. Verify that one matching executable is running and record its resident memory.
4. Retain one review bundle only. Remove test runners, copied package repositories, DerivedData intermediates, and module caches after the bundle is prepared.
5. Pause playback between checks and before handing the Mac back to the user.

Never launch a second copy to work around focus, window, or LaunchServices problems. Resolve the existing process or quit and relaunch it.

## Automate only app-scoped UI

Use the computer-use app surface for reversible UI checks. Attach to the exact review bundle path and inspect its own windows and menus.

- Exercise keyboard commands through the focused Canis97 window.
- Verify a pasteboard action by pasting into a temporary Canis97 text field, then restore that field's prior value.
- Prefer Canis97 accessibility identifiers and menu elements over coordinates.
- Do not open Finder, enumerate the desktop, capture the full screen, or inspect unrelated applications to locate a control.
- Do not run broad per-pixel accessibility scans of the macOS menu bar. They are slow, can destabilize a remote session, and expose unrelated status items.
- If a system-owned surface such as `MenuBarExtra` has no safely scoped automation target, compile its code and leave that one interaction for focused human review. State the limitation plainly.

Remote access changes what the user can hear and which display owns the menu bar. Keep audio checks app-muted and avoid asking the user to synthesize shortcuts or locate windows on another display when the same behavior can be proven from app-scoped automation and state.

## Govern live operations

Live authentication, catalog, metadata, tune, and playback checks require explicit owner authorization. Once authorized:

- keep exactly one live app and one in-flight operation;
- do not retry automatically;
- stop on an unknown authentication, entitlement, or provider state;
- never log or capture credentials, tokens, cookies, URLs, response bodies, or playback keys.

An allowed package fixture test or build-only compile does not authorize a live operation.

## Clean up and report

When testing ends or the machine becomes unstable:

1. Pause playback and quit the review app.
2. Stop only processes started by the current task.
3. Remove only task-owned scratch directories, helper binaries, screenshots, and logs.
4. Recheck process count and retained disk usage.
5. Report the exact commands, results, any authorized live activity, remaining manual checks, and the final process/artifact state.

Do not stage, commit, push, reset, restore, clean, or stash as part of this workflow unless the user separately requests that Git action.
