# Phase 1: Safe Interoperability Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-16
**Phase:** 01-safe-interoperability-foundation
**Areas discussed:** Sign-in surface

---

## Authentication Surface Preference

| Option | Description | Selected |
|--------|-------------|----------|
| Native form only | Collect credentials in a native app form and authenticate directly with SiriusXM. | |
| First-party browser only | Send the user through SiriusXM's website and accept only a clean authentication return. | |
| Strict hybrid | Prefer the browser path but retain a native fallback. | |
| Evidence-selected single path | Determine what SiriusXM safely supports, then ship exactly one path. | ✓ |

**User's choice:** The answer depends on what the SiriusXM website supports and how strict it is about factors such as user agent.

**Notes:** This was resolved as a research-driven choice: use a clean first-party browser return if it works; otherwise use a safe native direct-to-SiriusXM flow if that works. Do not scrape cookies, spoof a user agent, or ship both paths.

---

## Unsupported Authentication State

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated compatibility screen | Clearly explain that authentication is unsupported and offer safe next actions. | ✓ |
| Simple sign-in failure | Return the user to the sign-in form with a generic error. | |
| Signed-out app shell | Allow access to the broader app while remaining unauthenticated. | |

**User's choice:** Dedicated compatibility screen.

**Notes:** The screen must say that no credentials were retained and no workaround was attempted. It should offer Retry, the official SiriusXM site, and safe redacted diagnostics.

---

## Multiple Sign-In Paths

| Option | Description | Selected |
|--------|-------------|----------|
| Recommended path with manual fallback | Present one default method but retain another fallback. | |
| Ask every time | Let the user select an authentication method for each sign-in. | |
| Remember last successful method | Keep both methods and reuse the last one that worked. | |
| Exactly one proven method | Ship the browser method if proven; otherwise ship the native method if proven. | ✓ |

**User's choice:** “We're not building multiple sign-in paths. If browser works, we'll do that. If native works, we'll do that.”

**Notes:** There is no method selector and no runtime fallback. Failure of the selected proof means the project reports authentication as unsupported.

---

## Authentication Viability Proof

| Option | Description | Selected |
|--------|-------------|----------|
| Repeatable authorized smoke test | Require separate successful sign-in, entitlement, and sign-out runs before continuing. | ✓ |
| Single successful sign-in | Treat one observed success as sufficient evidence. | |
| Research evidence only | Proceed based on protocol research without an end-to-end authorized proof. | |

**User's choice:** Require the repeatable proof before doing the work of building the rest of the app; if authentication does not work, there is no point.

**Notes:** The user additionally required that testing not trigger bot detection. Because upstream detection cannot be guaranteed, the agreed implementation boundary is conservative and non-evasive: two manually initiated runs, one attempt at a time, no automated retry or rapid probing, and an immediate stop on CAPTCHA, challenges, 403, 429, rate-limit signals, unexpected redirects, or suspected bot responses.

---

## Discussion Completion

The user chose to finish after the sign-in surface area and create Phase 1 context. No additional gray areas were opened.

## the Agent's Discretion

- Exact internal type, protocol, and module names.
- The manual smoke-test harness and the non-secret evidence it records.
- Conservative timing and cooldown details.
- Redacted diagnostic taxonomy and wording.
- Unit and integration test organization.

## Deferred Ideas

None.
