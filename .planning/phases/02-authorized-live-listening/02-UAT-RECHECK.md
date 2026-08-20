---
status: blocked
phase: 02-authorized-live-listening
plan: "18"
date: 2026-08-20
scope: automatic-restore-and-bounded-listening
---

# Phase 02 Restore and Listening Checkpoint

This sanitized recheck is distinct from the original UAT and authentication checkpoint. It records fixed semantic outcomes only; it retains no credential, token, Keychain value, account identifier, provider payload, browser content, request, response, URL, header, media key, or stream detail.

## Preconditions

| Gate | Evidence | Status |
| --- | --- | --- |
| Durable authentication | `02-AUTH-UAT.md` records passed native authentication, entitlement, persistence, and fixed Keychain-item existence. | PASS |
| Playback readiness | `02-16-SUMMARY.md` records green Incremental Gate 5. | PASS |

## Integrated Offline Preflight

| Check | Result |
| --- | --- |
| No-host authentication matrix | PASS (14/14 synthetic cases) |
| SiriusXMClient package suite | PASS (87 tests) |
| Fake single-instance launcher and native launcher routing | PASS |
| Guarded macOS authentication/WebView/playback/metadata tests | PASS (69 tests; zero SiriusMac processes before and after) |
| Project lint and guarded project listing | PASS (zero SiriusMac processes before and after guarded listing) |
| Build-only | PASS (no production launch) |

Durable Keychain and browser state were not accessed or changed during preflight. The original `02-UAT.md` and `02-AUTH-UAT.md` remain unchanged.

## Restore and Listening Checkpoint

| Check | Result | Fixed evidence |
| --- | --- | --- |
| Exact telemetry-first launch | PASS | One newly built application was launched after the green preflight. |
| Automatic restoration | PASS | Native entitled listening composition appeared without a WebView or password entry. |
| Catalog refresh and selection | PASS | One entitled live-channel catalog refresh completed and one channel was selected. |
| Natural start | PASS | The selected channel reached confirmed playing state. |
| Pause | PASS | Playback reached confirmed paused state once. |
| Resume Live | PASS | One live-edge resume returned to confirmed playing state. |
| Stop | PASS | Playback reached stopped state once. |
| Current metadata | PASS | Channel-identity fallback was visible; richer artwork was unavailable and is recorded as unavailable rather than invented. |
| Final process invariant | BLOCKED | Final exact-process verification found two SiriusMac processes. Both were closed; no process remains. |

automatic_restore: completed
catalog_refresh: passed
listening_controls: passed
current_metadata: passed
process_invariant: blocked

## Closed Outcome

The bounded restore/listening sequence completed without a WebView, password entry, sign-out, local-session clearing, credential inspection, request capture, forced fault, retry, or second authorized launcher invocation. However, the required final one-process invariant was not met: two separate SiriusMac processes were present after the observation. Both copies were closed to restore the safe zero-process state.

This checkpoint is **BLOCKED**. No relaunch is permitted under this authorization, and no Plan 02-18 summary is created. A future attempt requires fresh owner authorization for one new exact-build observation.

## Authorized Recheck Addendum

| Check | Result | Fixed evidence |
| --- | --- | --- |
| Zero-before launch invariant | PASS | No SiriusMac process existed before the authorized launcher. |
| Exact telemetry-first launch | PASS | One freshly built bundle was launched through the native single-instance launcher. |
| Exact process identity | PASS | One SiriusMac PID was present and its mapped executable matched the freshly built bundle before and after the attempted accessibility attachment. |
| Native accessibility attachment | BLOCKED | The non-launching accessibility bridge timed out twice while targeting the already-running exact bundle. No additional launcher, app-open operation, or UI action was attempted. |
| Restore/listening observation | NOT OBSERVED | Because the accessibility bridge could not attach, automatic restoration, catalog, controls, and metadata were not claimed or interacted with. |

The one-process invariant remained satisfied. The exact intended app is left running and untouched; no WebView, password entry, credential inspection, sign-out, local-session clearing, request capture, recovery/expiry induction, retry, or relaunch occurred. This addendum supersedes neither the original bounded UAT nor the earlier completed listening evidence; it records only the unobservable result of this separately authorized recheck.

## Accessibility Connector Diagnosis Addendum

| Check | Result | Fixed evidence |
| --- | --- | --- |
| Existing exact process before inspection | PASS | One intended freshly built SiriusMac process existed before accessibility inspection. |
| Computer Use inspection | BLOCKED | A nominally non-launching app-state lookup injected a second SiriusMac process from a different Xcode build location before returning the existing app tree. No UI control was operated. |
| Safety cleanup | PASS | Both processes were closed immediately after the duplicate was detected; zero SiriusMac processes remain. |
| Replacement attachment proof | PASS | A PID-targeted System Events accessibility query attached to an already-running harmless macOS process without launching or activating another application. |

The duplicate source is therefore isolated to app-name lookup in the Computer Use connector, not the native single-instance launcher. Any future recheck must avoid Computer Use app lookup entirely and target only the existing SiriusMac PID through System Events. This addendum authorizes no launch by itself.

## PID-Targeted Authorized Recheck Addendum

| Check | Result | Fixed evidence |
| --- | --- | --- |
| Zero-before launch invariant | PASS | The process table contained zero SiriusMac processes before the authorized launcher ran. |
| Exact telemetry-first launch | PASS | The native single-instance launcher produced one exact SiriusMac PID mapped to the freshly built bundle. |
| PID-targeted accessibility binding | PASS | System Events bound only through the numeric PID; no application-name lookup, Computer Use connector, `open`, or alternate launcher was used. |
| Automatic restoration | BLOCKED | The automatic restore did not settle to native ready composition within this checkpoint. The exact process exposed zero accessibility windows and zero fixed listening/sign-in controls, so no catalog or playback action was possible. |
| WebView/password/sign-in handoff | NOT INVOKED | No WebView, password entry, credential handling, retry, Sign Out, Clear Local Session, or Keychain modification occurred. |
| Final process invariant | PASS | One SiriusMac process remained, and its executable path matched the newly built bundle. |

automatic_restore: blocked
catalog_refresh: not_observed
listening_controls: not_observed
current_metadata: not_observed
process_invariant: passed

## Latest Closed Outcome

This fresh owner-authorized attempt is **BLOCKED** at the fixed automatic-restore stage. It performed exactly one guarded production launch and retained exactly one expected process. Because restore did not reach the native listening composition, the checkpoint did not refresh the catalog, select a channel, tune, control playback, or observe metadata. No second launch, sign-in, WebView, cleanup, fault induction, request variation, traffic capture, or secret inspection is authorized by this record.
