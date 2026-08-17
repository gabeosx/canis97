import AuthFeasibilityCore
import Darwin
import Foundation

enum RunnerError: Error {
    case invalidArguments
    case failed
}

struct Arguments {
    let values: [String]

    func value(named name: String) throws -> String {
        guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else {
            throw RunnerError.invalidArguments
        }
        return values[index + 1]
    }

    func positional(_ index: Int) throws -> String {
        guard values.indices.contains(index), !values[index].hasPrefix("--") else {
            throw RunnerError.invalidArguments
        }
        return values[index]
    }

    func contains(_ flag: String) -> Bool {
        values.contains(flag)
    }
}

func readArtifact(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func writeArtifact(_ text: String, to path: String) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func replace(_ temporary: URL, target: URL) throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: target.path) {
        _ = try manager.replaceItemAt(target, withItemAt: temporary)
    } else {
        try manager.moveItem(at: temporary, to: target)
    }
}

func closeUnsupported(_ arguments: Arguments) throws {
    let reasonValue = try arguments.value(named: "--reason")
    guard let reason = ClosureReason(rawValue: reasonValue) else { throw RunnerError.invalidArguments }
    let targets = [
        try arguments.value(named: "--evidence"),
        try arguments.value(named: "--selection"),
        try arguments.value(named: "--owner-result"),
        try arguments.value(named: "--decision"),
    ].map(URL.init(fileURLWithPath:))
    let bundle = ArtifactBundle.canonicalUnsupported(reason: reason)
    try bundle.validate()
    let contents = [bundle.evidence, bundle.selection, bundle.ownerResult, bundle.decision]
    var temporaryURLs: [URL] = []
    defer { temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

    for (target, content) in zip(targets, contents) {
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".auth-feasibility-\(UUID().uuidString).tmp")
        try content.write(to: temporary, atomically: false, encoding: .utf8)
        temporaryURLs.append(temporary)
    }
    for (temporary, target) in zip(temporaryURLs, targets) {
        try replace(temporary, target: target)
    }
    FileHandle.standardOutput.write(Data("closed\n".utf8))
}

func validateBundle(_ arguments: Arguments) throws {
    let bundle = ArtifactBundle(
        evidence: try readArtifact(try arguments.positional(0)),
        selection: try readArtifact(try arguments.positional(1)),
        ownerResult: try readArtifact(try arguments.positional(2)),
        decision: try readArtifact(try arguments.positional(3))
    )
    try bundle.validate()
    FileHandle.standardOutput.write(Data("valid\n".utf8))
}

func requirePhaseOneGo(_ arguments: Arguments) throws {
    let bundle = ArtifactBundle(
        evidence: try readArtifact(try arguments.positional(0)),
        selection: try readArtifact(try arguments.positional(1)),
        ownerResult: try readArtifact(try arguments.positional(2)),
        decision: try readArtifact(try arguments.positional(3))
    )
    try bundle.validate()
    let decision = try Decision.parse(bundle.decision)
    guard decision.continuation == .unlocked,
          decision.value == FeasibilityDecision.browserReturn.rawValue || decision.value == FeasibilityDecision.nativeDirect.rawValue else {
        throw RunnerError.failed
    }
    FileHandle.standardOutput.write(Data("phase-one-go\n".utf8))
}

func deriveExperimentReadiness(_ arguments: Arguments) throws {
    let contract = try AuthExperimentContract.parse(readArtifact(try arguments.value(named: "--contract")))
    let readiness = try CandidateSelection.experimentReadiness(for: contract)
    try writeArtifact(readiness.canonicalText(contractDigest: contract.digest), to: arguments.value(named: "--output"))
}

func recordExperimentApproval(_ arguments: Arguments) throws {
    guard arguments.contains("--owner-approved") else { throw RunnerError.invalidArguments }
    let contract = try AuthExperimentContract.parse(readArtifact(try arguments.value(named: "--contract")))
    let approval = try ExperimentApproval.record(for: contract)
    try writeArtifact(approval.canonicalText, to: arguments.value(named: "--output"))
}

func validateExperimentApproval(_ arguments: Arguments) throws {
    let contract = try AuthExperimentContract.parse(readArtifact(try arguments.value(named: "--contract")))
    let approval = try ExperimentApproval.parse(readArtifact(try arguments.value(named: "--approval")))
    try approval.validate(against: contract)
    FileHandle.standardOutput.write(Data("valid\n".utf8))
}

func validateBrowserLaunchGate(_ arguments: Arguments) throws {
    let toolchainArtifact = try readArtifact(try arguments.positional(0))
    let contract = try AuthExperimentContract.parse(readArtifact(try arguments.positional(1)))
    let approval = try ExperimentApproval.parse(readArtifact(try arguments.positional(2)))
    try BrowserLaunchGate.validate(
        toolchainArtifact: toolchainArtifact,
        contract: contract,
        approval: approval
    )
    FileHandle.standardOutput.write(Data("valid\n".utf8))
}

func validateLiveResult(_ arguments: Arguments) throws {
    _ = try OwnerResult.parse(readArtifact(try arguments.positional(0)))
    FileHandle.standardOutput.write(Data("valid\n".utf8))
}

func recordBrowserRenewalPending(_ arguments: Arguments) throws {
    let probe = BrowserProbeResult.renewalPending
    let nativeApproval = NativeDirectApproval.notApplicable
    let bundle = ArtifactBundle.canonicalRenewalPending()
    try bundle.validate()

    let targets = [
        (try arguments.value(named: "--probe"), probe.canonicalText),
        (try arguments.value(named: "--evidence"), bundle.evidence),
        (try arguments.value(named: "--selection"), bundle.selection),
        (try arguments.value(named: "--owner-result"), bundle.ownerResult),
        (try arguments.value(named: "--decision"), bundle.decision),
        (try arguments.value(named: "--native-approval"), nativeApproval.canonicalText),
    ].map { (URL(fileURLWithPath: $0.0), $0.1) }

    for (target, content) in targets {
        try content.write(to: target, atomically: true, encoding: .utf8)
    }
    FileHandle.standardOutput.write(Data("recorded\n".utf8))
}

func validateNativeApproval(_ arguments: Arguments) throws {
    guard arguments.contains("--owner-approved") else { throw RunnerError.invalidArguments }
    let contract = try AuthExperimentContract.parse(readArtifact(try arguments.value(named: "--contract")))
    let ruleOut = try EvidenceRecord.parse(readArtifact(try arguments.value(named: "--rule-out")))
    let nativePurpose = try readArtifact(try arguments.value(named: "--native-purpose"))
    try contract.native.validate()
    guard nativePurpose == contract.canonicalText,
          ruleOut.browser == .ruledOut,
          ruleOut.native != .complete,
          ruleOut.candidateCount == 0 else {
        throw RunnerError.failed
    }
    FileHandle.standardOutput.write(Data("valid\n".utf8))
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { return }
    let parsed = Arguments(values: Array(arguments.dropFirst()))

    switch command {
    case "validate-auth-experiment-contract":
        _ = try AuthExperimentContract.parse(readArtifact(try parsed.positional(0)))
    case "derive-experiment-readiness":
        try deriveExperimentReadiness(parsed)
    case "record-experiment-approval":
        try recordExperimentApproval(parsed)
    case "validate-experiment-approval":
        try validateExperimentApproval(parsed)
    case "validate-browser-launch-gate":
        try validateBrowserLaunchGate(parsed)
    case "record-browser-renewal-pending":
        try recordBrowserRenewalPending(parsed)
    case "record-browser-not-applicable", "record-native-not-applicable":
        try closeUnsupported(parsed)
    case "validate-live-result":
        try validateLiveResult(parsed)
    case "validate-native-approval":
        if parsed.values.count == 1 {
            _ = try NativeDirectApproval.parse(readArtifact(try parsed.positional(0)))
            FileHandle.standardOutput.write(Data("valid\n".utf8))
        } else {
            try validateNativeApproval(parsed)
        }
    case "validate-evidence":
        _ = try EvidenceRecord.parse(readArtifact(try parsed.positional(0)))
    case "derive-selection":
        let evidence = try EvidenceRecord.parse(readArtifact(try parsed.value(named: "--evidence")))
        try writeArtifact(CandidateSelection.derive(evidence).canonicalText, to: parsed.value(named: "--output"))
    case "validate-selection":
        _ = try Selection.parse(readArtifact(try parsed.positional(0)))
    case "validate-owner-result":
        _ = try OwnerResult.parse(readArtifact(try parsed.positional(0)))
    case "derive-decision":
        let evidence = try EvidenceRecord.parse(readArtifact(try parsed.value(named: "--evidence")))
        let selection = try Selection.parse(readArtifact(try parsed.value(named: "--selection")))
        let owner = try OwnerResult.parse(readArtifact(try parsed.value(named: "--owner-result")))
        let decision = try DecisionGate.derive(evidence: evidence, selection: selection, ownerResult: owner)
        try writeArtifact(decision.canonicalText, to: parsed.value(named: "--output"))
    case "validate-decision":
        _ = try Decision.parse(readArtifact(try parsed.positional(0)))
    case "close-unsupported":
        try closeUnsupported(parsed)
    case "validate-bundle":
        try validateBundle(parsed)
    case "require-phase-one-go":
        try requirePhaseOneGo(parsed)
    default:
        throw RunnerError.invalidArguments
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("validation failed\n".utf8))
    exit(1)
}
