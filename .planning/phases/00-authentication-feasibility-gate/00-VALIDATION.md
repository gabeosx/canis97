---
phase: 00
slug: authentication-feasibility-gate
status: planned
nyquist_compliant: true
updated: 2026-08-17
---

# Phase 00 — Corrected Validation Strategy

All Swift commands are pinned to Xcode and isolated cache paths. They use
synthetic/canonical inputs only and never open provider content, request owner
credentials, or perform live traffic.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache
```

## Task-to-Verification Map

| Task | Timing | Exact automated verification | Expected result |
|---|---|---|---|
| 00-14-01 | pre-owner | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift test --package-path Spikes/AuthenticationFeasibility --filter EntitlementContractTests` | Profile and entitlement remain separate; contract is canonical. |
| 00-14-02 | pre-owner | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift test --package-path Spikes/AuthenticationFeasibility --filter WebSessionBridgeTests` | Authentication, entitlement, sign-out, and cleanup are latched semantically. |
| 00-15-01 | pre-owner | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift test --package-path Spikes/AuthenticationFeasibility --filter DecisionGateTests && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift test --package-path Spikes/AuthenticationFeasibility --filter FinalizationGateTests` | v3 accepts only zero-run unsupported or two ordered complete browser-return runs. |
| 00-16-01 | post-owner, supported only | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-live-result <owner-result-v3>` | The app-reported semantic v3 owner result is canonical; this command does not drive UI. |
| 00-16-02 | post-owner or zero-run unsupported | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/sirius-auth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sirius-auth-swiftpm-cache swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility finalize-phase --entitlement-contract <contract> --browser-probe <browser-probe-v3> --owner-result <owner-result-v3> --evidence-output <evidence> --selection-output <selection> --owner-result-output <installed-owner-result> --decision-output <decision>` | The staged quartet rederives, byte-validates, installs, and revalidates without accepting historical v2 or testimony. |

## Pre-Owner Gate

Before any owner-facing operation, run 00-14-01, 00-14-02, and 00-15-01. A
supported entitlement contract and passing suite are both required. Unsupported
entitlement uses `record-browser-unsupported --entitlement-contract <contract>
--output <browser-probe-v3>` and proceeds only through the zero-run NO-GO
finalizer branch.

## Post-Owner Gate

Only the supported branch presents the owner runbook. The finalizer accepts
exactly run-1, owner-confirmed cooldown, run-2, with authentication,
entitlement, signed-out, and cleanup all complete. It rejects v2, one/three
runs, duplicates, mixed paths, terminal/incomplete fields, and byte tampering.
No validation maps renewal, tune/key authorization, or playback to Phase 0.
