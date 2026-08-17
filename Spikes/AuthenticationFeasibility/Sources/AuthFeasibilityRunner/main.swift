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

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { return }
    let parsed = Arguments(values: Array(arguments.dropFirst()))

    switch command {
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
