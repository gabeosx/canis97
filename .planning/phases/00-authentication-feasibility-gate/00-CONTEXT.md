# Phase 0: Authentication Feasibility Gate - Context

**Gathered:** 2026-08-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a trustworthy GO or NO-GO decision about SiriusXM authentication before executing the production foundation. Phase 0 may build only the smallest isolated harness needed to evaluate one evidence-selected path and record safe semantic outcomes.

It does not build the production app shell, public `SiriusXMClient` API, Keychain persistence, catalog, playback, skins, updater, packaging, or release infrastructure. Those remain in later phases and cannot begin without a Phase 0 GO result.
</domain>

<decisions>
## Implementation Decisions

### Ordered single-path feasibility

- Evaluate a clean first-party, app-bound real-browser return first.
- Browser feasibility requires explicit first-party evidence for a fixed callback/return contract. A visible website sign-in, browser cookie, copied token, or inspectable redirect is not sufficient.
- If browser return is safely ruled out, evaluate one minimal native direct-to-SiriusXM path that identifies itself honestly.
- Do not build, retain, or offer both methods. There is no selector, automatic fallback, or preference-based choice.
- If neither candidate works safely, the decision is `NO-GO unsupported`.
- **Reversibility:** Costly. The selected result controls whether the production project proceeds and which adapter contract Phase 1 consumes.

### Human-only live proof

- The account owner—not an agent—initiates every live authentication attempt and operates any real browser or account surface.
- A GO result requires two separate runs through the same sole path.
- Each run must explicitly reach authenticated-and-entitled state and then clean sign-out.
- Only one attempt may be in flight. There is no automatic retry, polling, concurrency, rapid repetition, scheduled execution, or CI integration.
- The account owner chooses and confirms a conservative cooldown between the two runs.

### Immediate stop policy

- Stop immediately on CAPTCHA, interstitial challenge, MFA requirement that cannot be completed normally, HTTP 403 or 429, explicit rate limiting, unexpected redirect, suspected bot response, device/geographic/subscription/DRM control, or ambiguous entitlement evidence.
- Do not spoof a browser, user agent, device, client identity, or request fingerprint.
- Do not inspect or export browser cookies, storage, profiles, tokens, authenticated developer-tools data, raw request/response bodies, or account identifiers.
- A stop signal produces `NO-GO unsupported`; it does not trigger another method or workaround.

### Decision artifact and downstream gate

- Produce exactly one sanitized result: `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`.
- Safe evidence may contain build/harness version, rounded date, opaque run labels, semantic dispositions, public first-party reference URLs, cooldown confirmation, and cleanup result.
- Safe evidence must not contain credentials, tokens, cookies, account identifiers, raw payloads, token-bearing URLs, or browser/session state.
- Phase 1 can execute only after a GO result backed by both proof runs. NO-GO ends production implementation rather than degrading into speculative app work.

### Minimal disposable harness

- Reuse Foundation, SwiftPM, Swift Testing, and OS logging/privacy primitives; add no third-party dependency unless a concrete gap is proven and reviewed.
- Keep POC code isolated from production targets and easy to delete or promote selectively after the decision.
- The harness must expose semantic outcomes and stop conditions, never raw provider data.

### Agent Discretion

- Exact harness target/file names and internal protocol/type names.
- Safe closed vocabulary for semantic run dispositions and evidence fields.
- Offline synthetic fixtures and deterministic tests used before any account-owner attempt.
- Conservative cooldown guidance, provided the account owner controls and confirms it.
</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md` — project constraints, native scope, and no-bypass policy.
- `.planning/REQUIREMENTS.md` — `FEAS-01` through `FEAS-05` and downstream production requirements.
- `.planning/ROADMAP.md` — Phase 0 goal, hard Phase 1 dependency, and scope fence.
- `.planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md` — original authentication decisions and two-run proof requirement.
- `.planning/phases/01-safe-interoperability-foundation/01-RESEARCH.md` — platform guidance and unresolved provider-specific feasibility facts.
- `.planning/research/ARCHITECTURE.md` — reusable-client and volatile-adapter boundaries.
- `.planning/research/PITFALLS.md` — upstream-change, secret-handling, and access-control risks.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- No application code exists. Phase 1 planning artifacts describe intended production boundaries but have not been executed.

### Established Patterns

- Fail closed on unknown/provider-protected behavior.
- Keep volatile wire details behind replaceable internal seams.
- Use ephemeral transport, semantic diagnostics, and synthetic fixtures.
- Keep all live subscriber activity human-initiated and outside routine CI.

### Integration Points

- Phase 0 writes a sanitized decision artifact consumed as a hard precondition by Phase 1.
- Any reusable code promoted later must enter Phase 1 deliberately; Phase 0 does not silently become the public SDK.
</code_context>

<specifics>
## Specific Ideas

- Treat Phase 0 as a kill switch for the entire product investment, not as an early demo.
- Prefer a tiny SwiftPM command-line or test harness when possible; use the smallest native app callback surface only if browser-return evidence requires it.
- A successful technical login without explicit entitlement and clean sign-out is not a GO result.
</specifics>

<deferred>
## Deferred Ideas

- Production client API, Keychain persistence, compatibility UI, catalog, playback, macOS integration, skins, and release work remain in Phases 1–5.
</deferred>

---

*Phase: 00-authentication-feasibility-gate*
*Context gathered: 2026-08-16*
