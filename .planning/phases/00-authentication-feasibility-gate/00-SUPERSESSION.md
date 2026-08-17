Schema: phase-0-supersession-v1
Replan selected on: 2026-08-17
Replan choice: replan-from-scratch
Status: replacement-finalized
Historical plan range: 00-01..00-04
Active plan range: 00-05..00-16
Historical summaries authority: immutable-history-only
Existing quartet authority: historical-fail-closed-only
Replacement execution complete: yes
Phase 1 continuation: blocked
Current status authority: newly-byte-derived-and-validated-canonical-quartet
Post-finalization authority: newly-byte-derived-and-validated-canonical-quartet

The user explicitly selected replan-from-scratch on 2026-08-17. Summaries 00-01 through 00-04 remain immutable historical execution records, but they are not the active plan inventory and do not establish completion of the replacement execution.

The existing terminal quartet at `00-EVIDENCE.md`, `00-SELECTION.md`, `00-OWNER-RESULT.md`, and `00-DECISION.md` remains historical and fail-closed while replanning and replacement execution are in progress. Its `NO-GO unsupported` result is safe because it cannot unlock Phase 1, but it must not be treated as proof that Plans 00-05 through 00-13 have executed.

Plans 00-05 through 00-16 are the sole active replacement plans. Plans 00-14 through 00-16 correct the former renewal, tune/key, playback, and native-direct closure rules: only canonical v3 authentication, entitlement, sign-out, cleanup, and ordered-run evidence is active. During replanning and execution, this supersession record plus that active plan set are authoritative for Phase 0 status, and no Phase 1 continuation is authorized.

Plan 00-16 finalized the canonical unsupported branch without launching the harness or requesting owner activity. Only the newly byte-derived, atomically written, and validated v3 canonical quartet at the exact established paths is authoritative. Phase 1 must independently rederive and validate that quartet through the `auth-feasibility` executable, and only `GO browser-return` may unlock continuation. No stale artifact may be copied forward or hand-edited into authority.
