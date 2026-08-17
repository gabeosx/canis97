# Phase 0 Owner-Operated Browser Proof Runbook

## Checkpoint Status

The bounded browser experiment is eligible for presentation only after the
offline current-SDK, experiment-contract, exact owner-approval, conditional
source-graph, full synthetic-suite, and browser-preflight gates pass. This
runbook records that preparation; it does not launch a browser, contact
SiriusXM, or establish feasibility.

The current approved construction is bound to contract digest
`573f6ba270924112`. Open third-party callback documentation remains
non-dispositive and does not loosen any other gate.

## Owner Boundary

- Only the account owner may start the live surface, operate it, enter
  credentials, handle provider controls, confirm audible playback, request
  sign-out, and choose the cooldown between runs.
- Automation must never type, inspect, infer, record, screenshot, or export
  credentials, cookies, tokens, headers, account data, browser storage,
  provider responses, stream URLs, or playback keys.
- The executor stops before live presentation and accepts only a fixed,
  account-detail-free result class after the owner is finished.

## Fixed Browser Protocol

1. Complete one normal owner-operated browser proof run and confirm audible
   playback only if it was actually heard.
2. Request sign-out and wait for verified local cleanup before considering a
   second run.
3. Choose and observe a cooldown yourself, then start exactly one distinct
   second run.
4. A complete browser proof requires the ordered semantic milestones in both
   runs and legitimate renewal in at least one. Renewal-pending and ordinary
   no-clean-return remain incomplete.

## Stop Rules

The first CAPTCHA, MFA, challenge, protection, access-control signal,
rate-limit, redirect anomaly, suspicion, unknown state, or ambiguity is
terminal. Do not repeat, retry, switch paths, alter identity or headers, or
attempt a workaround. Native-direct is not exposed unless a later validator
proves strict WebKit-specific rule-out and a separate owner disclosure decision
is recorded.

## Allowed Resume Signals

Return exactly one of the following, with no account or provider details:

- `not-applicable`
- `browser-complete`
- `browser-incomplete`
- `renewal-still-pending`
- `strict-webkit-ruleout`
- `terminal-stop`

## Phase Boundary

This checkpoint does not produce `GO`, `NO-GO`, native approval, a replacement
decision, or a Phase 1 unlock. Those require later canonical semantic evidence
and validators.
