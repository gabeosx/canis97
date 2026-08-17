# Phase 0 Owner-Operated Browser-Return Runbook

## Before Any Owner Activity

The harness reports either `unsupported` entitlement or `supported` entitlement.
No owner activity is permitted unless it reports `supported` and the synthetic
DecisionGate and FinalizationGate suites pass. `unsupported` is finalized as
`NO-GO unsupported` with zero browser runs; it opens no provider UI and makes
no provider request.

## Owner Steps

1. When the app reports that run-1 is ready, start it yourself and complete the
   normal SiriusXM sign-in surface. Do not share credentials or account details.
2. Read only the app-reported semantic result: authentication, entitlement,
   signed-out, and cleanup must all be complete. Any protected, challenged,
   rate-limited, or ambiguous result ends the protocol.
3. Confirm sign-out and cleanup in the app, then choose and confirm a cooldown.
4. Start exactly one run-2. The app reports the same four semantic results.
5. The app finalizes only after both ordered runs are complete. Do not inspect
   traffic, cookies, developer tools, responses, stream URLs, or account data.

## App-Reported Outcomes

- `GO browser-return` — two complete ordered v3 runs, owner-confirmed cooldown,
  sign-out absence, and cleanup were validated mechanically.
- `NO-GO unsupported` — entitlement was unsupported before owner activity, or a
  terminal protected/ambiguous stop was recorded. Phase 1 remains blocked.
- `incomplete` — a required semantic state is absent or contradictory. Do not
  retry, switch paths, or attempt a workaround.

## Explicit Exclusions

Renewal, tune/key authorization, audible playback, catalog access, and
native-direct authentication are not owner steps or Phase 0 closure conditions.
They are deferred to the owning later phases.
