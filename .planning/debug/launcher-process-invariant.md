---
status: blocked
trigger: "ok go"
created: 2026-08-20T16:20:00-04:00
updated: 2026-08-20T13:30:17-04:00
---

# Debug Session: Launcher Process Invariant

## Symptoms

expected: |
  The telemetry-first launcher starts logging, opens exactly the just-built SiriusMac bundle once,
  verifies one PID whose executable path matches the built binary, and keeps that process available
  for the owner-operated authentication checkpoint.
actual: |
  The authorized Plan 02-17 attempts ended with zero SiriusMac processes. The latest telemetry wrapper
  emitted only `process-stage: launch-command-failed` before WebView sign-in, but an upstream no-stage
  wrapper failure was not yet distinguishable from that label.
errors: |
  Sanitized evidence only: `process: invariant_failed`. No raw telemetry, provider material, credential,
  cookie, header, body, URL, account, or Keychain secret may be inspected.
timeline: |
  First observed on 2026-08-20 during the first fresh Phase 02 authentication checkpoint after the
  single-instance launcher changes. Fake launcher tests, offline authentication tests, guarded Xcode
  tests, and build-only had passed. It is unknown whether the live telemetry mode ever worked after
  the launcher changes.
reproduction: |
  The live trigger is `script/build_and_run.sh --telemetry`, but the one authorized live authentication
  attempt was consumed. Do not run this or any other launch-capable mode during this debug session.

## Safety Boundary

- Diagnose and fix offline only.
- Do not launch, terminate, activate, inspect, or interact with production SiriusMac.
- Do not perform a second authentication attempt, open WebView, access Keychain, contact SiriusXM,
  inspect raw telemetry, or perform catalog/playback work.
- Verification is limited to fake-process tests, static inspection, SwiftPM tests, and build-only.
- Preserve the pre-existing `.planning/config.json` modification and untracked `.gsd/` directory.

## Current Focus

hypothesis: the consumed `launch-command-failed` observation remains unassigned because an upstream build, telemetry, lock, configuration, or absent-stage wrapper failure could previously reach the checkpoint without its own fixed label. The initial resolver and wait-window repairs remain in place.
bug_class: bohrbug
candidate_causes:
  - code: `resolve_process_binary.sh` compares argv[0] text rather than mapped executable identity.
  - code: `resolve_process_binary.sh` relies on a nonempty guard whose failure is not explicit in a conditional caller.
  - code: `single_instance_with_lock` invokes the whole launch function under an `||` condition, suppressing `errexit` and failure propagation.
  - code: `resolve_process_binary.sh` returns the first `lsof -d txt` mapping, although the Debug bundle statically contains both `SiriusMac` and `SiriusMac.debug.dylib`.
  - code: the two-second PID-registration budget can reject one asynchronous `open` before a newly launched GUI process appears.
  - code: `build_and_launch` did not classify failures before `open`, and `single_instance_with_lock` could emit no stage for an inner failure; downstream handling could therefore conflate that absence with `launch-command-failed`.
  - code: a failed lock acquisition could release a lock owned by another launcher process because ownership was not tracked.
  - environment: the built app could have exited before PID discovery; static inspection cannot prove or eliminate runtime exit.
and_gate: no — each candidate alone can produce the visible post-cleanup zero-process result.
test: fake-only coverage must prove distinct `lock-acquisition-failed`, `launcher-configuration-missing`, `build-command-failed`, `build-output-missing`, `telemetry-start-failed`, `launch-wrapper-no-stage-failed`, and true `launch-command-failed` labels, with no production commands reachable; then run the no-host authentication matrix and build-only. Do not launch or inspect SiriusMac in this session.
expecting: an absent inner stage is reported only as `launch-wrapper-no-stage-failed`, never as `launch-command-failed`; each pre-open path emits its own allow-listed fixed label.
next_action: the offline stage-propagation contract is green. Preserve `02-AUTH-UAT.md` as blocked and do not request or run another native launch automatically. Any future observation would require fresh owner authorization and may retain only one current allow-listed stage; it does not authorize authentication, WebView, Keychain, provider, catalog, or playback work.
reasoning_checkpoint:
  hypothesis: "The resolver can falsely reject the just-launched binary because it compares argv[0], and the lock wrapper can falsely report success because it invokes the launch-stage function in an errexit-ignored `||` context."
  confirming_evidence:
    - "A synthetic `/bin/sleep` process with forged argv[0] made the resolver return the forged path while `lsof -d txt` identified `/bin/sleep` as the mapped executable."
    - "A synthetic stage containing `false` then a succeeding statement ran the succeeding statement and let `single_instance_with_lock` return 0."
  falsification_test: "A fake mapped-executable source must be used instead of argv text, and a fresh child shell with `set -e` must exit nonzero before a post-failure side effect. Failure of either observation after its targeted repair falsifies the corresponding mechanism."
  fix_rationale: "Reading the mapped text executable establishes the identity being asserted, and executing the launch stage as a simple command preserves `set -e` at the production call site while explicitly returning its status in conditional test contexts."
  blind_spots: "Offline tests cannot establish which original native invariant clause failed, nor can they rule out a runtime app crash or OS-level launch failure."
  candidate_causes:
    - "code: argv-derived path resolution and an implicit empty-path guard fail the resolver identity contract."
    - "code: conditional wrapper invocation suppresses launch-stage fail-fast behavior."
    - "environment: the original application may still have exited before PID discovery."
  and_gate: "no — the confirmed code defects are independently sufficient protocol violations, and none is claimed as the proven cause of the consumed native failure."
tdd_checkpoint:

## Evidence

- timestamp: 2026-08-20T16:29:00-04:00
  checked: `script/build_and_run.sh`, `script/lib/single_instance_launcher.sh`, `script/lib/resolve_process_binary.sh`, and the full fake launcher matrix
  found: Every launch mode builds, opens the exact bundle once, waits for one name-matched PID, and then compares the resolver output byte-for-byte to `SIL_APP_BINARY`; a failed count or path comparison invokes cleanup, explaining why the terminal checkpoint observes zero processes. The fake `path` hook returns the fixture’s stored expected path directly, whereas production resolves `/bin/ps -o command=` and truncates it to the first shell word.
  implication: The fake matrix verifies helper control flow but does not verify the production resolver’s semantics; a resolver defect remains a concrete code candidate, while an app-startup exit remains a distinct environment/runtime candidate.

- timestamp: 2026-08-20T16:29:00-04:00
  checked: `02-AUTH-UAT.md` and Phase 02 Plan 15 summary
  found: The only sanctioned live attempt recorded `process: invariant_failed` with no substage, and the documented contract requires cleanup to zero on any failed invariant. Offline gates therefore cannot distinguish count-zero from exact-path mismatch without a synthetic experiment or separate launch authorization.
  implication: The live symptom is deterministic at the visible checkpoint boundary but has insufficient granularity to establish which invariant clause failed.

- timestamp: 2026-08-20T16:36:00-04:00
  checked: synthetic non-app `/bin/sleep` process run with forged argv[0], `script/lib/resolve_process_binary.sh`, and `/usr/sbin/lsof -d txt`
  found: For PID 59942, the production resolver returned `/tmp/pretend/SiriusMac`, matching forged argv[0]; `lsof` identified the mapped executable as `/bin/sleep`. The fake launcher matrix still passed because its path hook returns the expected fixture path rather than exercising this resolver.
  implication: The resolver does not establish executable identity and can deterministically create a false `invariant_failed` path comparison. This confirms a launcher code defect, but it does not yet prove the one live app used a noncanonical argv[0].

- timestamp: 2026-08-20T16:36:00-04:00
  checked: fake launcher matrix after the synthetic experiment
  found: `bash script/tests/build_and_run_tests.sh` passed; its expected lock-contender diagnostic was emitted and all fake launch/path/count cases passed.
  implication: Existing offline coverage remains green but lacks a production-resolver contract test.

- timestamp: 2026-08-20T16:36:00-04:00
  checked: Phase 1.25 spectrum-based fault localization eligibility
  found: No runnable test currently fails; the sole failure was an intentionally non-repeatable live checkpoint and has no per-test coverage spectrum.
  implication: SBFL is skipped; the leading class is `bohrbug` for the confirmed deterministic resolver defect, while the original live failure remains not reproducible under the safety boundary.

- timestamp: 2026-08-20T16:42:00-04:00
  checked: Phase 0 knowledge-base recall
  found: `mempalace` is unavailable and `.planning/debug/knowledge-base.md` does not exist, so no semantic or keyword candidate resolution is available.
  implication: No prior resolved incident is being used as a diagnosis shortcut.

- timestamp: 2026-08-20T16:42:00-04:00
  checked: synthetic `set -e` propagation experiment using `single_instance_with_lock` and a failing non-app launch-stage function
  found: The failing stage executed `false`, then continued to its following statement and made the wrapper return status 0. This is because `"$@" || status=$?` places the invoked function in an `errexit`-ignored conditional context.
  implication: A real `launch_after_build` invariant failure is not fail-fast at the caller boundary; telemetry mode can continue after the app has been cleaned up, obscuring the original failure and violating the launcher’s advertised fail-closed control flow.

- timestamp: 2026-08-20T16:47:00-04:00
  checked: `SiriusMac/SiriusMacApp.swift` and Debug target build settings
  found: Normal app launch constructs `AuthenticationView`; the only alternate scene is gated exclusively by `XCTestConfigurationFilePath` for app-hosted tests. No explicit `exit`, `fatalError`, application termination, or test-host flag is present in the normal entry point, and Debug has `CODE_SIGNING_ALLOWED = NO` with `DEBUG` defined.
  implication: Static inspection found no deterministic normal-startup termination branch, but cannot rule out a runtime crash or OS launch failure without the prohibited native launch observation.

- timestamp: 2026-08-20T17:10:00-04:00
  checked: agent-authored `bash script/tests/build_and_run_tests.sh` regression matrix before implementation changes
  found: The matrix exited 1 with `FAIL: process resolver must use an injectable mapped-text executable query`. The check intentionally completed before calling the old `/bin/ps` resolver, so no host-process inspection occurred.
  implication: The regression test is red for the confirmed resolver defect and is safe under the offline-only authorization boundary.

- timestamp: 2026-08-20T17:16:00-04:00
  checked: the same fake-process matrix after replacing argv-derived lookup and repairing wrapper invocation
  found: The mapped-executable and failure-propagation paths progressed, but the missing-mapping check failed with `FAIL: resolver must fail closed when no mapped executable is available`. The resolver's bare `[[ -n "$binary_path" ]]` did not force a nonzero exit in the conditional test caller.
  implication: The resolver needs an explicit empty-result exit branch; this is a newly observed offline hardening defect, not evidence about the consumed native attempt.

- timestamp: 2026-08-20T17:21:00-04:00
  checked: agent-authored `bash script/tests/build_and_run_tests.sh` regression matrix after the completed offline repair
  found: The matrix passed its exact mapped-path, wrong-path, missing-mapping, launch-stage failure-propagation, lock-release, pre-existing single-instance, and routing-contract cases. Its only diagnostic was the expected fake concurrent-lock message.
  implication: The repaired code satisfies the targeted offline launcher contracts; no native application or service interaction occurred.

- timestamp: 2026-08-20T17:25:00-04:00
  checked: shell syntax validation, ten repeated fake-process matrix runs, and the non-launching build-only path
  found: `bash -n` passed and the fake matrix passed 10/10 runs. The build-only process stopped at SwiftPM manifest-cache access with `Operation not permitted` for `/Users/gabe/Library/Caches/.../siriusxmclient.dia` (exit 74), before compilation; no app launch was requested.
  implication: Offline script verification is stable. The build result is inconclusive solely because the sandbox denied Xcode's normal local cache access, so the same build-only command needs scoped elevation.

- timestamp: 2026-08-20T17:30:00-04:00
  checked: elevated non-launching `bash script/build_and_run.sh --build-only`
  found: Xcode resolved the local `SiriusXMClient` package and completed `** BUILD SUCCEEDED **` at `/tmp/sirius-mac-derived-data/Build/Products/Debug/SiriusMac.app`. The invoked mode is `--build-only`; no open or process-control hook was called.
  implication: The focused launcher changes do not prevent the project from compiling. This is build-only evidence, not a native-launch result.

- timestamp: 2026-08-20T17:33:00-04:00
  checked: focused code diff, whitespace validation, and mutation-tool configuration
  found: `git diff --check` passed. The focused changes replace argv-derived identity with mapped-text identity, make the empty mapping explicit, preserve launch-stage status, and add fake-only contract coverage; they do not delete or bypass launcher behavior. No Stryker or other configured mutation tool was found.
  implication: The no-op/deletion signal passes. Mutation testing is explicitly skipped because this Bash project has no applicable configured tool.

- timestamp: 2026-08-20T17:36:00-04:00
  checked: fake-process matrix with only `single_instance_with_lock` temporarily reverted to `"$@" || status=$?`
  found: The matrix failed as predicted with `FAIL: lock wrapper must preserve launch-stage failure`; the resolver tests executed before it and remained fake-only.
  implication: The wrapper repair, rather than an unrelated change, prevents a failed launch stage from being converted to apparent success.

- timestamp: 2026-08-20T17:39:00-04:00
  checked: fake-process matrix after restoring the simple-command wrapper repair
  found: The matrix passed all fake launcher and routing-contract cases.
  implication: The wrapper repair reestablishes its targeted behavior before the independent resolver revert check.

- timestamp: 2026-08-20T17:42:00-04:00
  checked: fake-process matrix with only the resolver temporarily restored to the old argv-derived implementation
  found: The matrix failed as predicted with `FAIL: process resolver must use an injectable mapped-text executable query`. This structural test runs before any resolver execution, so `/bin/ps` was not invoked.
  implication: The mapped-text resolver repair, rather than another change, is necessary for the executable-identity contract.

- timestamp: 2026-08-20T17:46:00-04:00
  checked: final fake-process matrix and focused diff after both repairs were restored
  found: The matrix passed, `git diff --check` passed, and the diff contains only 105 targeted additions and 2 replacements across the resolver, lock helper, and fake-process test. Reverting either repair independently made its respective synthetic contract fail; reapplying returned the matrix to green.
  implication: Target test, no-op/deletion, adjacent shell-suite, and revert-and-reconfirm guardrail signals pass. Mutation testing remains skipped because no applicable tool is configured.

- timestamp: 2026-08-20T17:49:00-04:00
  checked: focused staged-file list and commit result
  found: Only `script/lib/resolve_process_binary.sh`, `script/lib/single_instance_launcher.sh`, and `script/tests/build_and_run_tests.sh` were staged and committed as `8eddadd` (`fix: harden launcher process invariant`). The pre-existing `.planning/config.json` modification and untracked `.gsd/` directory were not staged.
  implication: The evidence-backed offline repair is committed without altering user-owned workspace state. The debug session remains open because native UAT is intentionally prohibited here.

- timestamp: runtime-clock 2026-08-20T12:42:27-04:00 (recorded after the existing session chronology)
  checked: post-commit reconciliation of `8eddadd`, shell syntax, fake-process launcher matrix, and commit cleanliness for the three repaired launcher files
  found: `bash -n` passed; `bash script/tests/build_and_run_tests.sh` passed its fake single-instance matrix and routing contract; `git diff --check 8eddadd^ 8eddadd` and `git show --check 8eddadd` passed; the three repaired files exactly match `8eddadd`. The only remaining worktree changes are the pre-existing `.planning/config.json` modification, untracked `.gsd/`, and this untracked debug record.
  implication: The confirmed launcher defects remain fixed by reproducible offline evidence. The original native `invariant_failed` incident is still not proven resolved: no production process inspection, application launch, authentication, WebView, Keychain, telemetry, provider, catalog, or playback action occurred during reconciliation.

- timestamp: 2026-08-20T16:48:00-04:00
  checked: one separately user-authorized repaired telemetry-first launch of the exact newly built SiriusMac bundle
  found: The fixed launcher checkpoint result was `invariant_failed` before owner interaction.
  implication: The repaired offline contracts remain insufficient to establish the native launch invariant. The authentication checkpoint remains blocked; no retry or UI interaction was performed.

- timestamp: 2026-08-20T16:53:00-04:00
  checked: static Debug bundle metadata and Mach-O load commands, plus a fake `lsof -d txt -Fn` fixture with a leading `.debug.dylib` mapping followed by the expected executable
  found: The built bundle declares `SiriusMac` as `CFBundleExecutable` and contains both a `SiriusMac` executable and `SiriusMac.debug.dylib`; the executable loads the debug dylib. The old resolver returned the first mapping and the new synthetic test failed with the debug-dylib path instead of the expected executable.
  implication: First-mapping selection is an offline identity-contract defect that can create an indistinguishable generic invariant failure whenever text-mapping ordering places the debug dylib first. This does not claim that ordering was the consumed native failure's observed cause.

- timestamp: 2026-08-20T16:54:00-04:00
  checked: red/green fake-process regression matrix for fixed failure stages, delayed one-process registration, and expected-mapping selection; shell syntax; non-launching build-only
  found: Before implementation, the matrix failed because no fixed prelaunch stage was reported, then failed because the resolver returned the leading `.debug.dylib` fixture mapping. After repair, syntax validation and the full fake matrix passed. The launch path now waits up to ten seconds without reopening and reports only `prelaunch-cleanup-failed`, `launch-command-failed`, `zero-after-open`, `multiple-after-open`, `pid-selection-failed`, `mapped-path-missing`, or `mapped-path-mismatch`. `bash script/build_and_run.sh --build-only` completed with `BUILD SUCCEEDED`.
  implication: The launcher now preserves exact executable identity across multiple mappings, tolerates a bounded delayed registration, and leaves a closed sanitized diagnostic for any remaining native failure. No SiriusMac launch, process inspection, auth, Keychain, WebView, telemetry, provider, catalog, or playback operation occurred.

- timestamp: 2026-08-20T16:55:00-04:00
  checked: focused staged-file list, commit, and whitespace validation
  found: Only `script/lib/resolve_process_binary.sh`, `script/lib/single_instance_launcher.sh`, and `script/tests/build_and_run_tests.sh` were committed as `9f58c61` (`fix: diagnose launcher process stages`). The pre-existing `.planning/config.json` change, the sanitized checkpoint record, and untracked `.gsd/` directory were not staged.
  implication: The second offline launcher repair is durable and isolated from user-owned workspace state. The debug session stays blocked pending a separately authorized native attempt.

- timestamp: 2026-08-20T17:01:00-04:00
  checked: post-`9f58c61` commit reconciliation; shell syntax; fake-process launcher matrix; no-host authentication matrix; non-launching build-only; and the static route from `sil_report_invariant_stage` to `02-AUTH-UAT.md`
  found: The three repaired launcher files exactly match `9f58c61`; `bash -n` and the fake launcher matrix pass; the no-host authentication matrix passes all fixed-oracle and volatile-WebView isolation cases; and elevated `bash script/build_and_run.sh --build-only` reports `BUILD SUCCEEDED`. The unsandboxed reruns were necessary only because Xcode's normal compiler/module caches are outside the workspace. The repaired launcher emits one allow-listed `process-stage` label on stderr, but no script automatically transfers that label into `02-AUTH-UAT.md`; the present blocked artifact still contains only the earlier generic `process: invariant_failed` text.
  implication: All safe offline checks are green and no production process, launch, termination, credential, WebView, Keychain, telemetry, provider, catalog, or playback action occurred during this reconciliation. The original native failure remains unassigned because its fixed process stage was not retained; a fresh launch is the only remaining evidence, and any such authorization must capture only the fixed process-stage label before the checkpoint is rewritten.

- timestamp: 2026-08-20
  checked: one separately owner-authorized stage-reporting telemetry-first launch through `script/build_and_run.sh --telemetry`
  found: `process-stage: launch-command-failed`; post-failure cleanup was verified at zero SiriusMac processes.
  implication: The one-use observation failed before owner interaction. No retry, application UI interaction, sign-in, WebView, credential handoff, Keychain query, provider request, catalog action, or playback action occurred.

- timestamp: 2026-08-20T13:24:14-04:00
  checked: RED/green fake-only stage-propagation matrix for an absent inner stage, unavailable lock, missing launch configuration, failed build command, missing build output, failed telemetry start, and a true fake open-command failure
  found: Before repair the matrix failed at `wrapper preserves an absent inner stage` because the outer wrapper produced no label. After repair it passed: the absent-stage path emits only `launch-wrapper-no-stage-failed`, while the true fake opener failure remains `launch-command-failed`; the pre-open paths emit their separate allow-listed labels. The lock helper also keeps a failed contender from removing a lock it did not acquire.
  implication: The consumed `launch-command-failed` label cannot be retroactively attributed to the opener. Future offline diagnostics can distinguish it from all identified early wrapper paths without launching or inspecting SiriusMac.

- timestamp: 2026-08-20T13:24:14-04:00
  checked: shell syntax, `bash script/tests/build_and_run_tests.sh`, `bash script/test_offline_auth_matrix.sh`, and `bash script/build_and_run.sh --build-only`
  found: Syntax and the fake launcher matrix passed; the offline authentication matrix passed all listed fixed-oracle and WebView-isolation checks; build-only completed with `BUILD SUCCEEDED`. The latter two commands required scoped cache access outside the workspace, but neither launched or controlled the app.
  implication: The focused repair is green across the permitted offline checks. `02-AUTH-UAT.md` remains blocked, and no authentication, WebView, Keychain, provider, catalog, or playback action occurred.

- timestamp: 2026-08-20T13:30:17-04:00
  checked: the focused staged-file list, `git diff --cached --check`, shell syntax, fake-process launcher matrix, no-host authentication matrix, non-launching build-only path, and commit result
  found: Only `script/build_and_run.sh`, `script/lib/single_instance_launcher.sh`, and `script/tests/build_and_run_tests.sh` were committed as `d2cbdf2` (`fix: preserve launcher failure stages`). All permitted offline checks passed. The pre-existing `.planning/config.json` modification, the sanitized checkpoint artifact, this debug record, and untracked `.gsd/` were not staged.
  implication: The stage-propagation repair is durable and isolated. The consumed `launch-command-failed` datum remains historically ambiguous: it cannot prove that the configured open command, rather than a formerly-unlabeled earlier wrapper failure, was the original cause. A future observation from this revision would distinguish those paths, but none was requested or performed.

## Eliminated

## Resolution

root_cause: |
  Confirmed offline defects only (the consumed native failure remains unassigned):
  (1) `resolve_process_binary.sh` derives identity from argv[0] instead of the mapped text executable and relies on implicit `errexit` to reject an empty result;
  (2) `single_instance_with_lock` suppresses launch-stage failure propagation by invoking its command under `||`;
  (3) the resolver selects the first text mapping rather than the exact expected executable, despite Debug bundles mapping a debug dylib as well;
  (4) the two-second process-registration budget is unnecessarily brittle for one asynchronous GUI launch.
  (5) `build_and_launch` and its outer lock wrapper did not give every pre-open and absent-stage failure a distinct allow-listed label, so the saved `launch-command-failed` result is not sufficient evidence that `/usr/bin/open` itself failed.
fix:
  `resolve_process_binary.sh` now reads mapped `txt` executables through an injectable `lsof` command, explicitly fails closed for an empty result, and selects the exact expected executable when supplied. The launcher retains the PID-count observation and waits up to ten seconds for one process without reopening. `build_and_launch` now emits separate stages for build-command, build-output, and telemetry-start failures; the lock helper labels lock/configuration failures, tracks lock ownership, and reports an otherwise absent inner stage only as `launch-wrapper-no-stage-failed`. `launch-command-failed` is now reserved for the actual configured open command returning nonzero.
verification:
  target_test: { result: pass, suite: "bash script/tests/build_and_run_tests.sh" }
  mutation_check: { result: skipped, reason_if_skipped: "No Stryker or other Bash mutation tool is configured." }
  no_op_deletion: { result: pass, deletion_justified_by_rca: false, evidence: "Focused diff adds mapped-text resolution, explicit failure, and fake-only assertions; it does not remove or bypass behavior." }
  adjacent_tests: { result: pass, suites_run: ["bash -n script/build_and_run.sh script/lib/single_instance_launcher.sh script/tests/build_and_run_tests.sh", "bash script/tests/build_and_run_tests.sh", "bash script/test_offline_auth_matrix.sh", "bash script/build_and_run.sh --build-only"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, evidence: "Each repair was separately reverted and reproduced its contract failure, then restored to a green matrix." }
  guardrail_verdict: accepted
  build_only: { result: pass, command: "bash script/build_and_run.sh --build-only", note: "Xcode Debug build succeeded; no launch-capable mode ran." }
  commit: 8eddadd
  followup_commit: 9f58c61
  stage_propagation_commit: d2cbdf2
files_changed:
  - script/build_and_run.sh
  - script/lib/resolve_process_binary.sh
  - script/lib/single_instance_launcher.sh
  - script/tests/build_and_run_tests.sh
oracle_type: specified — the launcher contract explicitly requires the exact built executable identity and failure propagation from its launch stage.

## Native Verification Boundary

status: awaiting separate owner authorization

The separately authorized stage-reporting launch completed with `process-stage: launch-command-failed` and cleanup verified at zero SiriusMac processes. Its one-use authority is consumed. Return to offline investigation before requesting any new native launch authorization.

The offline repair is complete in `8eddadd`, `9f58c61`, and `d2cbdf2`. All earlier native-launch authority is consumed. No authentication, WebView, Keychain, provider, catalog, or playback behavior was entered by the observation.

The observation may persist exactly one failure datum, formatted as `process-stage: <label>`, where `<label>` is one of: `lock-acquisition-failed`, `launcher-configuration-missing`, `build-command-failed`, `build-output-missing`, `telemetry-start-failed`, `launch-wrapper-no-stage-failed`, `prelaunch-cleanup-failed`, `launch-command-failed`, `zero-after-open`, `multiple-after-open`, `unexpected-count-after-open`, `pid-selection-failed`, `mapped-path-missing`, or `mapped-path-mismatch`. All other process and telemetry output must be discarded. It must not inspect or record credentials, WebView/browser state, Keychain, provider data, catalog data, or playback data.

If the invariant passes, the observation ends without entering authentication. Authentication remains a separate owner authorization. If it fails, record only that one allow-listed label, close all copies through the existing helper, and halt. No result may be inferred from offline evidence.
