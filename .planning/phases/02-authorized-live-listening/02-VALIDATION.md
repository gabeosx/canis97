---
phase: 02
slug: authorized-live-listening
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-19
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing in `SiriusXMClient`; XCTest in the macOS app target |
| **Config file** | `Packages/SiriusXMClient/Package.swift` and `SiriusMac.xcodeproj/project.pbxproj` |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` |
| **Full phase command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningCompositionTests -only-testing:SiriusMacTests/PlaybackInstallationOrderTests -only-testing:SiriusMacTests/MetadataPresentationTests CODE_SIGNING_ALLOWED=NO` |
| **Observed runtime** | Package: 88 tests in 11 suites; app: 50 tests in 3 suites; both complete within the 60-second feedback budget |

---

## Sampling Rate

- **After every task commit:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient`
- **After every plan wave:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** Both package and app suites must be green, followed by the one bounded owner-visible live smoke test.
- **Max feedback latency:** 60 seconds for automated suites

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-W0-CAT01 | 02-01 | 0 | CAT-01 | T-02-04 | Filters only entitled standard and app-only `channel-linear` entities from invented fixtures. | unit/contract | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` | ✅ `LiveCatalogAdapterTests.swift` | ✅ green |
| 02-W0-CAT02 | 02-01 | 0 | CAT-02 | T-02-04 | Semantic channel snapshots preserve stable identity, optional presentation fields, entitlement, and freshness without raw provider objects. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` | ✅ `LiveCatalogAdapterTests.swift` | ✅ green |
| 02-W0-CAT03 | 02-01 | 0 | CAT-03 | T-02-03 | Stale catalog presence cannot authorize or begin playback. | unit/app | Full phase command above | ✅ catalog + composition suites | ✅ green |
| 02-W0-PLAY01 | 02-01 | 0 | PLAY-01 | T-02-01 | Tune, start, pause, resume-at-live-edge, and stop publish only confirmed one-player states. | unit/app | Full phase command above | ✅ playback + composition suites | ✅ green |
| 02-W0-PLAY02 | 02-01 | 0 | PLAY-02 | T-02-02 | Concurrent or superseded commands cannot install an obsolete player item or create a second coordinator. | unit/app | Full phase command above | ✅ playback + composition suites | ✅ green |
| 02-W0-PLAY03 | 02-01 | 0 | PLAY-03 | T-02-03 | Retry and re-resolution are bounded, cancellation-aware, and stop on protected-control or terminal authorization results. | unit/app | Full phase command above | ✅ playback + composition suites | ✅ green |
| 02-W0-PLAY04 | 02-01 | 0 | PLAY-04 | T-02-01 / T-02-03 | Authentication, entitlement, catalog, resolution, network, buffering, decoder, and unsupported-upstream states remain distinct without raw error text. | unit/app | Full phase command above | ✅ playback + composition suites | ✅ green |
| 02-W0-META01 | 02-01 | 0 | META-01 | T-02-04 | Active-generation metadata chooses best available text/artwork and falls back to stable channel identity. | unit/app | Full phase command above | ✅ metadata package + app suites | ✅ green |
| 02-W0-META02 | 02-01 | 0 | META-02 | Metadata failure cannot mutate healthy audio state and progresses through explicit stale/unavailable states. | unit/app | Full phase command above | ✅ metadata package + app suites | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Plan 02-01 created `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift` with invented provider-neutral filtering, stable identity, freshness, and no cache-as-authorization coverage for CAT-01 through CAT-03.
- [x] Plan 02-01 created `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift` with fake resolver/player/event coverage for PLAY-01 through PLAY-04, command supersession, and bounded recovery.
- [x] Plan 02-01 created `Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift` with injected clock/fake-flow coverage for META-01 and META-02.
- [x] Plan 02-01 created `SiriusMacTests/ListeningCompositionTests.swift` to prove one app composition-owned coordinator and confirmed-state presentation.
- [x] Plan 02-02 kept the first live-provider touch behind a blocking owner-visible checkpoint with explicit stop conditions and semantic-only evidence.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Current SiriusXM catalog/tune/metadata contract and one authorized AVFoundation stream work without a prohibited workaround. | CAT-01, CAT-02, PLAY-01, PLAY-04, META-01 | Provider contracts are undocumented and volatile; secrets, resolved resources, key material, and raw responses cannot become automated fixtures. Audible playback and protected-control behavior require owner observation. | From `/Users/gabe/sirius-mac`, run `./script/build_and_run.sh --telemetry`; reuse the already-authenticated app session; perform exactly one bounded catalog refresh and one owner-selected channel tune; confirm semantic lineup, current-live playback, pause/resume/stop, and best available metadata; retain only allow-listed outcome classes. Stop immediately on login requirement, unknown redirect, CAPTCHA/MFA, `403`, `429`, rate-limit/bot/control signal, DRM ambiguity, or any need to inspect/persist raw secrets or provider bodies. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all previously MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60 seconds
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated by retrospective Nyquist audit on 2026-08-20

## Validation Audit 2026-08-20

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

Current evidence: the package command passed 88 tests in 11 suites, and the focused app command passed 50 tests in `ListeningCompositionTests`, `PlaybackInstallationOrderTests`, and `MetadataPresentationTests`. Every Phase 02 requirement has targeted automated coverage; the retained live-provider smoke test remains manual-only because it requires an authorized subscriber session and owner observation.

Audit note: historical plans sometimes show `bash script/lib/single_instance_launcher.sh --guard-app-host -- ...`. That file is source-only, so direct execution does not dispatch the guarded function. This validation strategy records the directly executable `xcodebuild` command used by this audit; the historical command issue does not leave a requirement behavior uncovered.
