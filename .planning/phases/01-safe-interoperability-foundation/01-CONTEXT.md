# Phase 1: Safe Interoperability Foundation — Context

**Gathered:** 2026-08-16
**Architecture updated:** 2026-08-17
**Status:** Locked and ready to execute

<domain>
## Phase Boundary

Build and end an authorized SiriusXM subscriber session through a reusable Apple-platform client. Phase 1 includes the settled WebView-to-native authentication bridge, native authentication and entitlement verification, session ownership, Keychain-backed secret handling, sign-out cleanup, redacted diagnostics, and the foundational SwiftPM API. It does not implement catalog retrieval, playback, skins, or the full player experience.
</domain>

<decisions>
## Locked Implementation Decisions

### Authentication architecture

- Authentication feasibility is settled. Do not run more authentication experiments, derive a Phase 0 decision, or require a Phase 0 GO artifact.
- The one shipped path uses a user-operated, nonpersistent `WKWebView` owned by the native app.
- Only after an explicit user action may the bridge select exactly one current first-party `AUTH_TOKEN` cookie from the apex `siriusxm.com` domain or an accepted SiriusXM subdomain, decode only `session.accessToken`, and transfer it once in volatile memory to `SiriusXMClient`.
- The token is used only by client-owned native HTTPS requests to SiriusXM. No shared browser profile, arbitrary cookie/storage enumeration, JavaScript extraction, developer tooling, user-agent spoofing, challenge solving, or access-control bypass is permitted.
- The app never offers a method picker, native credential fallback, external-browser fallback, or automatic retry.

### Runtime authority and entitlement

- An active session is produced only by one runtime-owned sequence: extract token → verify authentication natively → verify entitlement natively → atomically publish session state.
- A caller, test fixture, summary, owner-result file, or planning artifact cannot assert authenticated or entitled state.
- Authentication and entitlement remain separate semantic results. Authentication without confirmed entitlement never unlocks the player or persists reusable material.
- Unknown response shapes, redirects, CAPTCHA/MFA/control challenges, 403/429, rate-limit signals, suspected bot responses, or ambiguity stop the attempt without a follow-up request.

### Secret lifecycle and sign-out

- Token/session material is actor-owned and ephemeral. Only reusable material explicitly allowed after authenticated-and-entitled success may enter the app-owned Keychain adapter.
- Extraction and sign-out use the same `FirstPartyTokenCookiePolicy`. Multiple matching cookies, unsupported domain/path values, expired ambiguity, or a remaining matching token makes cleanup incomplete.
- Sign-out retires active work and clears actor memory first, removes matching WebView cookies and Keychain material, and reports any incomplete cleanup without restoring the session.

### UI and compatibility

- The native sign-in surface hosts the one WKWebView path and presents typed loading, rejection, challenge, unsupported, authenticated-but-not-entitled, authenticated-and-entitled, signed-out, and cleanup-failure states.
- Unsupported compatibility is a complete native state with no partial player/library shell, workaround language, or alternate sign-in action.

### Testing

- Phase 1 uses deterministic synthetic WebKit stores, transports, clocks, credential stores, and diagnostics. It performs no feasibility proof run.
- Browser-bridge and native-request test targets always compile; mutable `.planning` files may not conditionally remove source or tests from the build graph.
- `00-REVIEW.md` is acceptance input: runtime-owned authority, mandatory entitlement, symmetric token cleanup, atomic state publication, and unconditional test compilation are blocking criteria.

### Agent discretion

- Exact internal type and target names, provided the public `SiriusXMClient` surface remains semantic and upstream wire/token details stay internal or in a narrowly scoped app-to-client credential seam.
- Exact safe diagnostic labels and fixed UI copy.
- Test organization and synthetic fixture shape, provided no live secret or provider response is recorded.
</decisions>

<canonical_refs>
## Canonical References

- `.planning/ROADMAP.md` — active phase order and success criteria.
- `.planning/REQUIREMENTS.md` — `AUTH-01`–`AUTH-03`, `SECR-01`–`SECR-03`, and `CLNT-01`–`CLNT-04`.
- `.planning/phases/00-authentication-feasibility-gate/00-REVIEW.md` — defects converted into Phase 1 regression criteria; not an execution gate.
- `Spikes/AuthenticationFeasibility/` — implementation reference for the settled token/native-request path; not an authority artifact.
- `.planning/phases/01-safe-interoperability-foundation/01-01-PLAN.md` through `01-08-PLAN.md` — executable plan sequence.

Earlier Phase 1 research that recommends a real-browser callback or a Phase 0 GO gate is superseded by this locked context.
</canonical_refs>

---

*Phase: 01-safe-interoperability-foundation*
*Architecture locked: 2026-08-17*
