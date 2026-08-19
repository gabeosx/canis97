---
status: resolved
trigger: "The first authorized Phase 02 live catalog request reached SiriusXM but returned the closed malformed-contract classification before any channel could be selected."
created: 2026-08-19T17:36:00Z
updated: 2026-08-19T15:06:00Z
---

## Current Focus

hypothesis: Resolved. The direct browse-at-edge candidate was configured but not the current Channels rendering path. The current browser resolves its fixed Channels navigation target through the API browse-page operation, whose page graph is admitted by the bounded decoder.
test: The catalog request remains an exact bearer GET with no body or query and targets only the current browser page route. Focused tests prove bounded page-graph acceptance and fail-closed behavior for malformed branches.
expecting: Met. One owner-authorized request produced only sanitized owner-selectable channel choices, with no tune, playback, metadata, artwork, or second request.
next_action: No further automated action. Leave the isolated app at owner channel selection; do not tune.
bug_class: bohrbug
reasoning_checkpoint: null
tdd_checkpoint: null

## Symptoms

expected: The exact allow-listed catalog GET decodes into a sanitized list of entitled linear channel identities and display names so the owner can select one tune target.
actual: Authentication restoration and transport succeeded, but the response was classified as malformed-contract and the checkpoint stopped before tune, playback, or metadata.
errors: "malformed-contract"
timeline: First occurred during the first exact content-contract request on 2026-08-19 after the closed catalog adapter was implemented.
reproduction: Launch the rebuilt checkpoint app, allow automatic Keychain restoration to reach Ready to listen, then run the exact catalog preflight once.

## Evidence

- timestamp: 2026-08-19T14:36:00Z
  checked: Current unauthenticated first-party player bundles named by 02-CONTENT-CONTRACT-RESEARCH.md
  found: The exact v2 catalog operation uses the already-present bearer authorization and has only an optional locale query input. Its browse renderer consumes page-graph items through item.entity.type, item.entity.id, and item.entity.texts.title.default.
  implication: No invented header or retry is needed. The checkpoint needs a bounded page-graph decoder and may retain only validated channel semantics.
- timestamp: 2026-08-19T14:36:00Z
  checked: Commit 06d2a8f catalog parser
  found: The parser rejects every document above 1,048,576 bytes before JSON parsing and only reads a flat name field for display. The fixed-route response was therefore capable of being rejected before any entity could be admitted.
  implication: A valid page graph with normal container/set/item metadata can fail as malformed-contract even when it contains an eligible linear channel.
- timestamp: 2026-08-19T14:40:27Z
  checked: Focused synthetic decoder tests through a directly loaded local XCTest bundle
  found: With the original parser, the first-party-shaped document produced terminal malformed-contract. With the corrected parser, the same document decoded one sanitized channel title; a document above the new eight-megabyte cap remained terminal malformed-contract.
  implication: The narrow repair both removes the proven false-negative boundary and retains a strict size limit.
- timestamp: 2026-08-19T14:49:00Z
  checked: One rebuilt exact isolated checkpoint app with automatic Keychain restoration
  found: The app reached Ready to listen and the single approved catalog check again stopped at malformed-contract. No channel selection, tune, playback, metadata, artwork, or second request occurred.
  implication: The size/title repair was necessary but insufficient. The previous closed terminal does not identify which remaining parser boundary fired and does not authorize guesswork about the response contract.
- timestamp: 2026-08-19T14:52:59Z
  checked: Focused synthetic decoder tests for a fixed failure classifier
  found: The classifier distinguishes only non-provider semantic atoms for non-JSON content, oversized documents, invalid JSON, unsupported roots, absent admissible channels, and invalid channel identities; the bounded nested page graph still decodes. Three focused tests passed.
  implication: A subsequent bounded check can narrow the failure boundary without exposing response material or broadening the request, destination, credentials, or accepted channel semantics.
- timestamp: 2026-08-19T14:55:00Z
  checked: One rebuilt exact isolated checkpoint app with automatic Keychain restoration and the fixed classifier
  found: The app again reached Ready to listen. The one approved catalog check stopped at the fixed no-admissible-channel atom. No channel selection, tune, playback, metadata, artwork, or second request occurred.
  implication: The transient response was valid JSON and did not reach any earlier size, content-type, JSON, or root-shape failure. It did not expose a candidate accepted by the native parser within its bounded traversal.
- timestamp: 2026-08-19T14:59:47Z
  checked: Current public first-party renderer plus focused synthetic nesting test
  found: The renderer reads an item through its nested entity object and does not establish a twelve-level provider limit. A synthetic explicit linear entity beyond the native traversal bound produced only the fixed nesting-limit atom; four focused tests passed.
  implication: One further bounded check can distinguish the native nesting boundary from a response that has no admissible channel under the current source-derived semantics, without relaxing the limit or accepting a new entity type.
- timestamp: 2026-08-19T15:02:00Z
  checked: One rebuilt exact isolated checkpoint app with a bounded thirty-two-level diagnostic scan
  found: The app reached Ready to listen and the one approved check again stopped at the nesting boundary. The diagnostic scan found no explicit admissible channel before its secondary bound; no channel selection, tune, playback, metadata, artwork, or second request occurred.
  implication: The direct candidate's valid JSON is not the current browser page graph within the source-derived entity semantics. Increasing the admitted traversal depth would be speculative and would not repair the request contract.
- timestamp: 2026-08-19T15:05:37Z
  checked: Current public first-party Channels navigation and page-fetch code
  found: The current Channels route resolves a fixed published navigation target, then the page flow calls the API browse-page operation. The direct browse-at-edge operation remains configured but is not the route used by that current renderer flow. Six focused request-contract and decoder tests passed after replacing the candidate with the fixed current page route.
  implication: The prior direct candidate was a contract-selection error, not evidence that the subscriber session had been lost. The next bounded confirmation now has a source-derived request and parser pairing.
- timestamp: 2026-08-19T15:06:00Z
  checked: One rebuilt exact isolated checkpoint app with automatic Keychain restoration and the current browser page route
  found: The app reached Ready to listen, then the one approved catalog check completed and displayed only sanitized owner-selectable channel choices. No channel was selected; no tune, playback, metadata, artwork, or second request occurred.
  implication: The current catalog contract and bounded decoder are compatible with the authenticated session. The app is left at the required owner-selection boundary.

## Eliminated

- hypothesis: The v2 request requires a non-secret header beyond bearer authorization or a required query parameter.
  evidence: The current first-party operation definition lists bearer authorization and only an optional locale input. The original request already supplied the fixed host, path, GET method, bearer authorization, and JSON accept header.
  timestamp: 2026-08-19T14:36:00Z
- hypothesis: The raw live response can be safely retained to learn its schema.
  evidence: The project contract prohibits retaining raw provider bodies. The first-party renderer provides enough public semantic structure to test the narrow parser correction without accessing or persisting the subscriber response.
  timestamp: 2026-08-19T14:36:00Z

## Eliminated

## Resolution

root_cause: The checkpoint initially imposed an unsupported one-megabyte cap and flat-name assumption, then sent a direct catalog operation that is configured in the public bundle but is not the current browser Channels path. The session itself restored automatically and reached the authenticated service; raw provider data remained intentionally unretained.
fix: Raise the transient catalog document cap to eight megabytes, retain the recursive explicit channel-linear/id admission rule, extract only a bounded nested title, classify remaining parser boundaries with fixed non-provider atoms, and use the current browser's fixed page route. The repair does not broaden destinations, methods, authorization, redirects, identifiers, or response-field acceptance.
verification: build-for-testing passed; focused tests passed for bounded page-graph acceptance, over-limit rejection, redacted classifier, nesting diagnostics, and the current browser page request contract. One isolated owner-authorized catalog confirmation automatically restored the Keychain session, completed successfully, and stopped before any tune request.
files_changed:
  - SiriusMac/Listening/ClosedLiveObservationAdapter.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMacTests/ListeningCompositionTests.swift
