---
schema_version: 1
open_count: 9
waived_count: 0
fixed_count: 1
total_count: 10
last_updated: 2026-08-18T18:11:48.668Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 00 | deviation | Spikes/AuthenticationFeasibility |  | SwiftPM local verification required host execution because sandbox compiler cache and manifest sandbox were unavailable. | fixed |  | 2026-08-17T13:22:15.472Z | 2026-08-17T13:22:31.501Z |
| 2 | 00 | deviation | .planning/phases/00-authentication-feasibility-gate/00-03-SUMMARY.md |  | Offline SwiftPM verification required the installed Xcode toolchain because the sandboxed Command Line Tools environment could not write its compiler cache. | open |  | 2026-08-17T13:31:16.481Z |  |
| 3 | 00 | deviation | Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift |  | Added Foundation import required for BrowserReturnContractTests compilation. | open |  | 2026-08-17T18:05:17.613Z |  |
| 4 | 00 | deviation | Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift |  | Conditionalized harness-only tests so blocked source graphs remain buildable. | open |  | 2026-08-17T18:05:17.692Z |  |
| 5 | 00 | deviation | Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RunProtocol.swift |  | Added the missing closed event contract referenced by the plan. | open |  | 2026-08-17T18:05:17.770Z |  |
| 6 | 00 | deviation | .planning/phases/01-safe-interoperability-foundation/01-01-PLAN.md |  | Approved cross-plan wiring added an executable fail-closed Phase 1 preflight. | open |  | 2026-08-17T19:15:53.911Z |  |
| 7 | 00 | deviation | Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift |  | Removed the impossible owner-artifact dependency from zero-run finalization. | open |  | 2026-08-17T22:18:30.328Z |  |
| 8 | 01 | stub | SiriusMac/Authentication/AuthenticationPresentationModel.swift | 234 | UncomposedAuthenticationPresentationFlow remains waiting-only until Plan 01-06 wires the nonpersistent WebKit bridge. | open |  | 2026-08-18T04:19:55.786Z |  |
| 9 | 01 | unrun-verify | SiriusMacTests/SelectedAuthenticationCompositionTests.swift |  | Focused XCTest composition verification is blocked by existing SiriusMacTests test-host linker configuration | open |  | 2026-08-18T11:28:29.131Z |  |
| 10 | 01 | deviation | SiriusMac.xcodeproj/project.pbxproj |  | Corrected a mismatched group file-reference identifier for RestorableAuthenticationCredentialSource.swift. | open |  | 2026-08-18T18:11:48.668Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "00",
    "file": "Spikes/AuthenticationFeasibility",
    "line": null,
    "description": "SwiftPM local verification required host execution because sandbox compiler cache and manifest sandbox were unavailable.",
    "status": "fixed",
    "reason": "",
    "recorded_at": "2026-08-17T13:22:15.472Z",
    "resolved_at": "2026-08-17T13:22:31.501Z"
  },
  {
    "id": 2,
    "kind": "deviation",
    "phase": "00",
    "file": ".planning/phases/00-authentication-feasibility-gate/00-03-SUMMARY.md",
    "line": null,
    "description": "Offline SwiftPM verification required the installed Xcode toolchain because the sandboxed Command Line Tools environment could not write its compiler cache.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T13:31:16.481Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "deviation",
    "phase": "00",
    "file": "Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift",
    "line": null,
    "description": "Added Foundation import required for BrowserReturnContractTests compilation.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T18:05:17.613Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "00",
    "file": "Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift",
    "line": null,
    "description": "Conditionalized harness-only tests so blocked source graphs remain buildable.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T18:05:17.692Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "00",
    "file": "Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RunProtocol.swift",
    "line": null,
    "description": "Added the missing closed event contract referenced by the plan.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T18:05:17.770Z",
    "resolved_at": null
  },
  {
    "id": 6,
    "kind": "deviation",
    "phase": "00",
    "file": ".planning/phases/01-safe-interoperability-foundation/01-01-PLAN.md",
    "line": null,
    "description": "Approved cross-plan wiring added an executable fail-closed Phase 1 preflight.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T19:15:53.911Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "deviation",
    "phase": "00",
    "file": "Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift",
    "line": null,
    "description": "Removed the impossible owner-artifact dependency from zero-run finalization.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T22:18:30.328Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "stub",
    "phase": "01",
    "file": "SiriusMac/Authentication/AuthenticationPresentationModel.swift",
    "line": 234,
    "description": "UncomposedAuthenticationPresentationFlow remains waiting-only until Plan 01-06 wires the nonpersistent WebKit bridge.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T04:19:55.786Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "unrun-verify",
    "phase": "01",
    "file": "SiriusMacTests/SelectedAuthenticationCompositionTests.swift",
    "line": null,
    "description": "Focused XCTest composition verification is blocked by existing SiriusMacTests test-host linker configuration",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T11:28:29.131Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "deviation",
    "phase": "01",
    "file": "SiriusMac.xcodeproj/project.pbxproj",
    "line": null,
    "description": "Corrected a mismatched group file-reference identifier for RestorableAuthenticationCredentialSource.swift.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T18:11:48.668Z",
    "resolved_at": null
  }
]
````
