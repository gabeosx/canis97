import Foundation

@main
struct ProductIdentityMigrationTests {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                failures.append(message)
            }
        }

        func makeOperations(
            sourceExists: Bool = true,
            destinationExists: Bool = false,
            markerExists: Bool = false,
            legacyData: Data = Data("legacy".utf8),
            projectedData: Data? = Data("projected".utf8),
            destinationData: Data? = nil,
            cancelled: Bool = false,
            failWrite: Bool = false,
            failMarker: Bool = false
        ) -> (ProductIdentityMigrationOperations, () -> [String]) {
            var events: [String] = []
            let operations = ProductIdentityMigrationOperations(
                sourceExists: { sourceExists },
                destinationExists: { destinationExists },
                completionMarkerExists: { markerExists },
                isCancelled: { cancelled },
                readSource: {
                    events.append("read-source")
                    return legacyData
                },
                projectSource: { source in
                    events.append("project-source")
                    return source == legacyData ? projectedData : nil
                },
                writeDestination: { data in
                    events.append("write-destination")
                    guard !failWrite, data == projectedData else { throw TestError.write }
                },
                readDestination: {
                    events.append("read-destination")
                    return destinationData ?? projectedData ?? Data()
                },
                verifyDestination: { projected, reread in
                    events.append("verify-destination")
                    return projected == reread
                },
                writeCompletionMarker: {
                    events.append("write-marker")
                    if failMarker { throw TestError.write }
                }
            )
            return (operations, { events })
        }

        do {
            let (operations, events) = makeOperations()
            expect(ProductIdentityMigration(operations: operations).perform() == .migrated, "valid source migrates")
            expect(events() == ["read-source", "project-source", "write-destination", "read-destination", "verify-destination", "write-marker"], "marker follows reread verification")
        }

        do {
            let (operations, events) = makeOperations(markerExists: true)
            expect(ProductIdentityMigration(operations: operations).perform() == .alreadyComplete, "marker is idempotent")
            expect(events().isEmpty, "completed migration does not read or overwrite state")
        }

        do {
            let (operations, events) = makeOperations(destinationExists: true)
            expect(ProductIdentityMigration(operations: operations).perform() == .destinationAuthoritative, "destination wins")
            expect(events().isEmpty, "destination is never overwritten")
        }

        do {
            let (operations, events) = makeOperations(sourceExists: false)
            expect(ProductIdentityMigration(operations: operations).perform() == .noSource, "missing source is a no-op")
            expect(events().isEmpty, "missing source is not read")
        }

        do {
            let (operations, events) = makeOperations(projectedData: nil)
            expect(ProductIdentityMigration(operations: operations).perform() == .rejectedSource, "malformed source is rejected")
            expect(!events().contains("write-destination"), "malformed source is never written")
        }

        do {
            let (operations, events) = makeOperations(cancelled: true)
            expect(ProductIdentityMigration(operations: operations).perform() == .rejectedSource, "cancelled work leaves migration incomplete")
            expect(events().isEmpty, "cancelled migration does not read or write")
        }

        do {
            let (operations, events) = makeOperations(failWrite: true)
            expect(ProductIdentityMigration(operations: operations).perform() == .failedDestination, "destination write failure is closed")
            expect(!events().contains("write-marker"), "write failure never marks completion")
        }

        do {
            let (operations, events) = makeOperations(destinationData: Data("mismatch".utf8))
            expect(ProductIdentityMigration(operations: operations).perform() == .failedDestination, "reread mismatch is closed")
            expect(!events().contains("write-marker"), "mismatch never marks completion")
        }

        do {
            let (operations, events) = makeOperations(failMarker: true)
            expect(ProductIdentityMigration(operations: operations).perform() == .failedDestination, "marker failure stays incomplete")
            expect(events().last == "write-marker", "marker is attempted only after verification")
        }

        if failures.isEmpty {
            print("product identity migration tests: PASS")
        } else {
            for failure in failures {
                fputs("FAIL: \(failure)\n", stderr)
            }
            exit(1)
        }
    }

    private enum TestError: Error {
        case write
    }
}
