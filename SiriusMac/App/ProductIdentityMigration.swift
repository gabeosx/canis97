import Foundation

/// The closed result of a destination-first migration of app-owned,
/// non-secret state. A legacy source is never removed by this transaction.
enum ProductIdentityMigrationOutcome: Equatable {
    case noSource
    case migrated
    case alreadyComplete
    case destinationAuthoritative
    case rejectedSource
    case failedDestination
}

/// Injected operations for a single semantic migration. The operation surface
/// intentionally contains no credential, Keychain, token, cookie, session,
/// provider, network, or logging callbacks.
struct ProductIdentityMigrationOperations {
    let sourceExists: () -> Bool
    let destinationExists: () -> Bool
    let completionMarkerExists: () -> Bool
    let isCancelled: () -> Bool
    let readSource: () throws -> Data
    let projectSource: (Data) -> Data?
    let writeDestination: (Data) throws -> Void
    let readDestination: () throws -> Data
    let verifyDestination: (Data, Data) -> Bool
    let writeCompletionMarker: () throws -> Void
}

/// A pure, destination-first transaction used by app-owned storage owners.
/// Its caller supplies semantic validation and projection instead of moving
/// opaque files between product namespaces.
struct ProductIdentityMigration {
    let operations: ProductIdentityMigrationOperations

    func perform() -> ProductIdentityMigrationOutcome {
        guard !operations.completionMarkerExists() else {
            return .alreadyComplete
        }
        guard !operations.destinationExists() else {
            return .destinationAuthoritative
        }
        guard !operations.isCancelled() else {
            return .rejectedSource
        }
        guard operations.sourceExists() else {
            return .noSource
        }
        guard let source = try? operations.readSource(),
              !operations.isCancelled(),
              let projected = operations.projectSource(source)
        else {
            return .rejectedSource
        }

        guard !operations.isCancelled() else {
            return .rejectedSource
        }

        do {
            try operations.writeDestination(projected)
            guard !operations.isCancelled() else {
                return .failedDestination
            }
            let reread = try operations.readDestination()
            guard operations.verifyDestination(projected, reread) else {
                return .failedDestination
            }
            guard !operations.isCancelled() else {
                return .failedDestination
            }
            try operations.writeCompletionMarker()
            return .migrated
        } catch {
            return .failedDestination
        }
    }
}
