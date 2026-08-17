---
phase: 00-authentication-feasibility-gate
reviewed: 2026-08-17T13:41:45Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - Spikes/AuthenticationFeasibility/Package.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/CandidateSelectionTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/ContractTracerTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/DecisionGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/StopConditionTests.swift
findings:
  critical: 4
  warning: 3
  info: 0
  total: 7
status: issues_found
---

# Phase 00: Code Review Report

**Reviewed:** 2026-08-17T13:41:45Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

The offline implementation contains no provider, browser, or account operation. However, its public derivation API and artifact validators do not consistently enforce the locked fail-closed contract. In particular, malformed evidence and contradictory closure state can still produce a GO, and several artifacts advertised as strict validators accept non-canonical content.

`swift test` could not be run in this review environment because the installed Swift compiler/SDK versions are incompatible and the compiler cannot write its module cache. This is an environment limitation, not a finding against the submitted source.

## Critical Issues

### CR-01: The public decision gate derives GO from an unvalidated evidence value

**Classification:** BLOCKER

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift:150`

**Issue:** `derive` validates only that the supplied selection equals `CandidateSelection.derive(evidence)`. That comparison, implemented at `CandidateSelection.swift:53-55`, does not call `EvidenceRecord.validate`. Since `EvidenceRecord` has a public memberwise-style initializer, a caller can construct evidence with `browser == .complete`, `candidateCount == 1`, and an invalid/non-public reference, pair it with two passing runs, and receive `GO browser-return`. The current test at `DecisionGateTests.swift:6-36` does exactly this using `synthetic-reference` and asserts the GO. This bypasses the required validated public-evidence predicate.

**Fix:** Validate the evidence at every public derivation boundary before selecting or unlocking.

```swift
public static func derive(
    evidence: EvidenceRecord,
    selection: Selection,
    ownerResult: OwnerResult
) throws -> Decision {
    try evidence.validate()
    try CandidateSelection.validate(selection, against: evidence)
    // existing owner-result validation and derivation
}
```

Use a syntactically valid allowed reference for the positive GO test, and add a regression test asserting that direct invalid evidence throws from `DecisionGate.derive`.

### CR-02: A closed/preflight-failed artifact can still unlock a GO

**Classification:** BLOCKER

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift:179-207`

**Issue:** `EvidenceRecord.validate` accepts any closed `ClosureReason` independently of the candidate state. Thus an otherwise complete supported candidate with `closureReason: candidate-preflight-failed` passes validation; after two passes, `DecisionGate.derive` returns GO. A preflight failure is explicitly a terminal closure reason and must result in the canonical unsupported branch, not coexist with a supported candidate.

**Fix:** Make closure state mutually exclusive with supported evidence. At minimum, require `closureReason == "none"` whenever `candidateCount == 1`, and require an explicit allowed closure reason for the zero-candidate closure branch if that is the intended schema. Add tests covering every `ClosureReason` combined with complete evidence and two passing runs.

### CR-03: Invalid calendar dates are accepted as valid evidence and can unlock GO

**Classification:** BLOCKER

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift:239-245`

**Issue:** `isRoundedDate` checks only character positions. Values such as `2026-99-99` and `2026-02-31` satisfy it, pass `EvidenceRecord.parse`, and can proceed through the CLI decision derivation to a GO. The final gate is required to close on malformed evidence; a non-existent date is malformed audit evidence.

**Fix:** Parse an exact `yyyy-MM-dd` date with a fixed Gregorian/UTC formatter (or validate `DateComponents`) and require round-trip equality before accepting it. Add invalid-month, invalid-day, and leap-day regression cases.

### CR-04: “Strict” validation accepts non-canonical artifacts, including GO bundles

**Classification:** BLOCKER

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift:200-208`

**Issue:** `ArtifactFields.parse` deliberately accepts fields in any order (`EvidenceContract.swift:212-231`). `ArtifactBundle.validate` byte-compares only selection and decision, not evidence or owner result, so reordered evidence/owner fields validate. The standalone `validate-evidence`, `validate-owner-result`, `validate-selection`, and `validate-decision` commands likewise only parse their artifact (`main.swift:76-92`). This contradicts the required complete canonical evidence→selection→owner→decision chain: a non-canonical, hand-authored GO bundle is treated as valid instead of being closed as tampered.

**Fix:** Have every artifact parser (or its corresponding validate command) reject input unless `parsed.canonicalText == input`, and have `ArtifactBundle.validate` compare all four parsed canonical texts to their source strings. Add reordered-field and non-canonical single-run placeholder tests for every validator and for a GO bundle.

## Warnings

### WR-01: A valid terminal owner result derives a decision that its own parser rejects

**Classification:** WARNING

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift:173-176`

**Issue:** For one valid terminal run on a supported path, this code creates `Decision(.unsupported, selectedPath: .browserReturn/.nativeDirect)`. `Decision.parse` requires a NO-GO decision to have `Selected path: unsupported` (`EvidenceContract.swift:64-65`), so `derive-decision` writes an artifact that `validate-decision` rejects. A normal terminal stop therefore cannot produce the required valid blocked decision.

**Fix:** Preserve the supported selection only in the owner result; emit the blocked decision with `.unsupported`.

```swift
return Decision(.unsupported, evidenceRevision: evidence.revision, selectedPath: .unsupported)
```

Add a test that serializes and parses the decision produced from every one-run terminal outcome.

### WR-02: Owner-result parsing normalizes an out-of-order terminal run into validity

**Classification:** WARNING

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift:98-128`

**Issue:** Parsing `Run 1: none`, `Run 2: run-2|browser-return|challenge`, and `Run count: 1` uses `compactMap`, collapsing the second physical slot into `runs[0]`. The single-run branch then omits a `run-1` label check and accepts it. This repairs malformed/out-of-order proof input rather than rejecting it as required; it also yields an object whose `canonicalText` cannot be parsed back.

**Fix:** Validate the physical field shape before constructing the run array: zero runs requires both `none`; one terminal run requires a non-`none` `Run 1` labelled `run-1` and `Run 2: none`; two runs require both ordered labels. Add the same `run-1` label check to the direct one-run `validate` branch.

### WR-03: The package does not declare the project’s current-macOS baseline

**Classification:** WARNING

**File:** `/Users/gabe/sirius-mac/Spikes/AuthenticationFeasibility/Package.swift:4-14`

**Issue:** The manifest declares no supported platform even though the project targets current macOS only and the executable imports Darwin. SwiftPM will advertise its default, much older macOS deployment baseline rather than the required current release, creating an inaccurate compatibility contract.

**Fix:** Declare the intended platform in the package manifest, for example:

```swift
let package = Package(
    name: "AuthenticationFeasibility",
    platforms: [.macOS(.v26)],
    // products and targets
)
```

---

_Reviewed: 2026-08-17T13:41:45Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
