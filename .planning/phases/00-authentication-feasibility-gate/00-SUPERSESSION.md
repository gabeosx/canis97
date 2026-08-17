Schema: phase-0-supersession-v1
Replan selected on: 2026-08-17
Replan choice: replan-from-scratch
Status: replacement-planned
Historical plan range: 00-01..00-04
Active plan range: 00-05..00-13
Historical summaries authority: immutable-history-only
Existing quartet authority: historical-fail-closed-only
Replacement execution complete: no
Phase 1 continuation: blocked
Current status authority: 00-SUPERSESSION.md+00-05..00-13
Post-finalization authority: newly-byte-derived-and-validated-canonical-quartet

The user explicitly selected replan-from-scratch on 2026-08-17. Summaries 00-01 through 00-04 remain immutable historical execution records, but they are not the active plan inventory and do not establish completion of the replacement execution.

The existing terminal quartet at `00-EVIDENCE.md`, `00-SELECTION.md`, `00-OWNER-RESULT.md`, and `00-DECISION.md` remains historical and fail-closed while replanning and replacement execution are in progress. Its `NO-GO unsupported` result is safe because it cannot unlock Phase 1, but it must not be treated as proof that Plans 00-05 through 00-13 have executed.

Plans 00-05 through 00-13 are the sole active replacement plans. During replanning and execution, this supersession record plus that active plan set are authoritative for Phase 0 status, and no Phase 1 continuation is authorized.

After successful Plan 00-13 finalization, only a newly byte-derived, atomically written, and validated canonical quartet at the exact established paths may become authoritative. Phase 1 must independently rederive and validate that quartet through the `auth-feasibility` executable, and only `GO browser-return` or `GO native-direct` may unlock continuation. No stale artifact may be copied forward or hand-edited into authority.
