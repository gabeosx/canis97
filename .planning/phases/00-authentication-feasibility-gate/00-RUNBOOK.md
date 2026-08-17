# Phase 0 Owner Runbook

## Selected Feasibility State

Live operation: prohibited

The canonical selection is `unsupported`. No browser-return or native-direct
candidate is present, and no owner action, authentication attempt, proof run,
cooldown, or checkpoint is permitted for this state.

## Deterministic Closure

The four canonical artifacts are the complete Phase 0 record. They must be
validated and freshly derived by the offline feasibility harness before they
can be consumed:

1. Validate the evidence artifact.
2. Derive selection from that evidence and require byte equality with the
   stored selection.
3. Validate the zero-run owner result.
4. Derive decision from the evidence, selection, and owner result and require
   byte equality with the stored decision.

Any missing, malformed, conflicting, or non-canonical artifact must be
replaced through the harness's `close-unsupported` operation. The canonical
unsupported closure is idempotent and never starts live work.

## Unsupported Branch Rules

- Do not create, compile, retain, or review a browser or native candidate.
- Do not open a browser, authenticate, enter credentials, inspect account or
  browser state, or contact a provider.
- Do not collect tokens, cookies, callback values, account identifiers, raw
  provider values, request/response data, or precise timing.
- Do not retry, poll, schedule, or substitute another method.
- Record the candidate safety review as `candidate-review=skipped-unsupported`.

## Terminal Outcome

The sole terminal outcome is `NO-GO unsupported`. Phase 1 continuation is
blocked. A new path can be considered only by a future, separately planned
evidence review; this runbook does not authorize discovery or live probing.
