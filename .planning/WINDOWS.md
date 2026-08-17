---
schema_version: 1
open_count: 5
waived_count: 0
fixed_count: 1
total_count: 6
last_updated: 2026-08-17T19:15:53.911Z
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
  }
]
````
