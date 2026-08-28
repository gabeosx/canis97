import Foundation

/// Stable, local-only identity for a saved song. The source channel and album
/// intentionally remain presentation context rather than identity inputs.
struct FavoriteSongIdentity: Hashable, Sendable {
    let normalizedTitle: String
    let normalizedArtist: String

    init?(title: String, artist: String) {
        guard let normalizedTitle = Self.normalize(title),
              let normalizedArtist = Self.normalize(artist)
        else { return nil }
        self.normalizedTitle = normalizedTitle
        self.normalizedArtist = normalizedArtist
    }

    /// Length-prefixing makes the two fields unambiguous without treating any
    /// delimiter as reserved song text.
    var storageKey: String {
        "\(normalizedTitle.utf8.count):\(normalizedTitle)\(normalizedArtist.utf8.count):\(normalizedArtist)"
    }

    static func normalize(_ value: String) -> String? {
        let canonical = value.precomposedStringWithCanonicalMapping
        let collapsed = canonical
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

/// Non-tunable presentation context for the channel that supplied a confirmed
/// current song. It deliberately contains no catalog or playback authority.
struct FavoriteSongSourceChannel: Equatable, Hashable, Sendable {
    let rawIdentity: String
    let name: String?
    let displayNumber: Int?

    init?(rawIdentity: String, name: String?, displayNumber: Int?) {
        let identity = rawIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return nil }
        self.rawIdentity = identity
        self.name = Self.trimmed(name)
        self.displayNumber = displayNumber
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// The fixed, non-secret value boundary between confirmed metadata and durable
/// library state. It has no provider payload, artwork, resource, or session data.
struct FavoriteSongSnapshot: Equatable, Hashable, Sendable {
    let identity: FavoriteSongIdentity
    let title: String
    let artist: String
    let albumName: String?
    let sourceChannel: FavoriteSongSourceChannel
    let savedAt: Date

    init?(
        title: String,
        artist: String,
        albumName: String? = nil,
        sourceChannel: FavoriteSongSourceChannel,
        savedAt: Date = Date()
    ) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !artist.isEmpty,
              let identity = FavoriteSongIdentity(title: title, artist: artist)
        else { return nil }
        self.identity = identity
        self.title = title
        self.artist = artist
        self.albumName = Self.trimmed(albumName)
        self.sourceChannel = sourceChannel
        self.savedAt = savedAt
    }

    var copyText: String { "\(artist) — \(title)" }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// Closed durable outcomes keep callers from inferring success from optimistic
/// in-memory state when the app's local store is unavailable.
enum FavoriteSongMutationResult: Equatable, Sendable {
    case saved
    case removed
    case failed
}
