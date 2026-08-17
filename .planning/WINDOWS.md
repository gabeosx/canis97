---
schema_version: 1
open_count: 0
waived_count: 0
fixed_count: 1
total_count: 1
last_updated: 2026-08-17T13:22:31.501Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 00 | deviation | Spikes/AuthenticationFeasibility |  | SwiftPM local verification required host execution because sandbox compiler cache and manifest sandbox were unavailable. | fixed |  | 2026-08-17T13:22:15.472Z | 2026-08-17T13:22:31.501Z |

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
  }
]
````
