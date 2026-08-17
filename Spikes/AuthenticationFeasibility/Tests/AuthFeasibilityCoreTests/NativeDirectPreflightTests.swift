import Foundation
import Testing
@testable import AuthFeasibilityCore

@Test("not-applicable native branch has no credential or runtime source")
func notApplicableBranchKeepsNativeSourcesAbsent() throws {
    #expect(NativeBranchClosure.current == .notApplicable)
    #expect(!NativeBranchClosure.runtimeSourcePermitted)

    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceDirectory = packageRoot.appendingPathComponent("Sources/AuthFeasibilityHarness")
    let packageManifest = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)

    #expect(!FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("NativeCredentialSession.swift").path))
    #expect(!FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("NativeDirectRuntime.swift").path))
    #expect(!packageManifest.contains("NativeCredentialSession"))
    #expect(!packageManifest.contains("NativeDirectRuntime"))
}
