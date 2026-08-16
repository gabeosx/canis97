# Phase 1: Safe Interoperability Foundation - Context

**Gathered:** 2026-08-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish and end an authorized SiriusXM subscriber session safely through a reusable, public Apple-platform client boundary. This phase must prove that one supportable authentication path works before catalog, playback, library, media-control, or final player UI work begins.

The phase includes authentication-path validation, explicit session outcomes, entitlement confirmation, secure credential handling, sign-out cleanup, redacted diagnostics, and the foundational SwiftPM client API. It does not implement the station catalog, audio playback, skins, or the full application experience.
</domain>

<decisions>
## Implementation Decisions

### Single authentication path

- Authentication is selected by evidence, not by a predetermined UI preference.
- Investigate a clean first-party browser authentication return first. If it works safely and reliably, that is the sole shipped sign-in path.
- If browser authentication cannot provide a clean supported return, investigate a native direct-to-SiriusXM flow. If that works safely and reliably, that is the sole shipped sign-in path.
- Do not ship both paths, a method selector, or a fallback from one method to the other.
- Do not scrape browser cookies or storage, spoof a user agent, solve challenges, bypass access controls, or conceal the app's identity.
- If neither path works within these constraints, authentication is unsupported and the project does not proceed to later phases.
- **Reversibility:** Costly. The selected sign-in surface affects the public client contract, app shell, security model, and downstream architecture.

### Unsupported-authentication experience

- Present a dedicated compatibility screen when safe authentication is unavailable.
- State clearly that authentication is unsupported.
- Explain that no credentials were retained and no workaround was attempted.
- Offer Retry, a link to the official SiriusXM site, and safe redacted diagnostics.
- Fail closed. Do not expose a partially authenticated app shell or imply playback should work.

### Required viability proof

- Authentication is a hard continuation gate for Phases 2–5.
- Complete two separate, manually initiated authorized smoke-test runs using the one selected sign-in path.
- Each run must sign in, receive a confirmed authenticated and entitled response, and sign out cleanly.
- The proof is not an automated loop and is not part of routine CI.
- Permit only one attempt in flight. Do not automatically retry, probe concurrently, or repeat rapidly.
- Stop immediately on CAPTCHA, an interstitial challenge, HTTP 403 or 429, an explicit rate-limit signal, an unexpected redirect, or any suspected bot-detection response.
- Browser authentication must use the user's real browser. Native authentication must identify the app honestly.
- If either run fails or produces ambiguous evidence, document authentication as unsupported and halt work on Phases 2–5.
- **Reversibility:** Costly. Relaxing this gate later would invalidate the project's safety and viability assumptions.

### Agent Discretion

- Exact internal protocol, type, and module names within the public-library boundary.
- Shape of the manual smoke-test harness and the non-secret evidence it records.
- Conservative timing and cooldown choices for manually initiated tests.
- Redacted diagnostic categories and wording, provided no credential, token, cookie, account, or sensitive request data is exposed.
- Unit and integration test organization, provided the manual two-run gate remains separate from routine CI.
</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md` — project vision, constraints, architecture principles, distribution model, and public-library requirement.
- `.planning/REQUIREMENTS.md` — Phase 1 authentication, security, and client-library requirements (`AUTH-01`–`AUTH-03`, `SECR-01`–`SECR-03`, `CLNT-01`–`CLNT-04`).
- `.planning/ROADMAP.md` — Phase 1 goal, dependencies, success criteria, and the prohibition on later work before authentication is proven.
- `.planning/research/SUMMARY.md` — synthesized stack and implementation recommendations.
- `.planning/research/ARCHITECTURE.md` — reusable-client boundary, adapter isolation, and dependency direction.
- `.planning/research/PITFALLS.md` — authentication, reverse-engineering, secret-handling, and upstream-change failure modes.
- `.planning/research/STACK.md` — native macOS and Swift toolchain recommendations.

No external specification or ADR supersedes these project planning documents.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- None. This is a greenfield repository with planning artifacts only.

### Established Patterns

- No implementation patterns exist yet.
- Planning establishes a native macOS app, a local SwiftPM package for the reusable SiriusXM layer, volatile upstream behavior behind adapters, fail-closed authentication, and native Keychain-backed secret storage.

### Integration Points

- A new native macOS application target will consume the reusable SiriusXM client package.
- The public client package owns typed session outcomes and SiriusXM interoperability contracts without exposing volatile transport details.
- Keychain access and other app-specific platform services connect through narrow boundaries so the library remains independently testable and reusable on Apple platforms.
</code_context>

<specifics>
## Specific Ideas

- Treat the reusable SiriusXM layer as a first-class library in the spirit of `libghostty` relative to Ghostty: independently useful, publicly documented, and consumed by the app rather than embedded as incidental app code.
- Prove authentication before investing in the rest of the player. A beautiful app without a safe working session path has no product value.
- Make the unsupported state honest and useful rather than disguising it as a generic sign-in error.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope.
</deferred>

---

*Phase: 01-safe-interoperability-foundation*
*Context gathered: 2026-08-16*
