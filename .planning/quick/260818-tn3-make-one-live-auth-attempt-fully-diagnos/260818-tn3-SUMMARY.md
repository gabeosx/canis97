---
quick_id: 260818-tn3
status: complete
description: Make one live auth attempt fully diagnosable with secret-free native reason labels
code_commit: 2b51d30
completed: 2026-08-18
---

# Secret-safe native authentication diagnostics summary

- Preserved closed transport classes for timeout, name resolution, connection, TLS, cancellation, and unknown failures without retaining error text or URLs.
- Distinguished missing, HTML, and other content types; client, server, and unsupported HTTP families; empty, malformed, and wrong-root JSON; and each settled entitlement-shape failure.
- Kept the diagnostic sink limited to fixed operation/outcome labels. Tests prove secret-bearing error descriptions and failing URLs cannot reach rendered diagnostics.
- Confirmed the exact live WebKit shape remains accepted when `AUTH_TOKEN` is current, root-path, and on `siriusxm.com` or a true subdomain even when WebKit reports `isSecure == false`.
- All 35 SiriusXMClient package tests passed, all 46 SiriusMac app tests passed, and `./script/build_and_run.sh --build-only` succeeded.

The verification made no SiriusXM request and did not launch a sign-in flow.
