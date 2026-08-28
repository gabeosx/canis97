import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

private func source(_ rawIdentity: String = "channel-7", _ name: String? = "Seven", _ number: Int? = 7) -> FavoriteSongSourceChannel {
    guard let source = FavoriteSongSourceChannel(
        rawIdentity: rawIdentity,
        name: name,
        displayNumber: number
    ) else { fatalError("valid source channel fixture rejected") }
    return source
}

private func snapshot(
    title: String = "  Teardrop  ",
    artist: String = "  Massive Attack  ",
    albumName: String? = nil,
    sourceChannel: FavoriteSongSourceChannel = source(),
    savedAt: Date = Date(timeIntervalSince1970: 1)
) -> FavoriteSongSnapshot {
    guard let snapshot = FavoriteSongSnapshot(
        title: title,
        artist: artist,
        albumName: albumName,
        sourceChannel: sourceChannel,
        savedAt: savedAt
    ) else { fatalError("valid song fixture rejected") }
    return snapshot
}

let normalized = snapshot(title: "  Teardrop\t\n Song  ", artist: "  MASSIVE\n  ATTACK  ")
let caseVariant = snapshot(title: "teardrop song", artist: "massive attack")
expect(normalized.identity == caseVariant.identity, "case and whitespace variants must share identity")

let unicodeComposed = snapshot(title: "Beyoncé", artist: "SÓL")
let unicodeDecomposed = snapshot(title: "Beyonce\u{301}", artist: "SO\u{301}L")
expect(unicodeComposed.identity == unicodeDecomposed.identity, "canonical Unicode variants must share identity")

let nonASCIICase = snapshot(title: "Ångström", artist: "MØ")
let nonASCIICaseVariant = snapshot(title: "ångström", artist: "mø")
expect(nonASCIICase.identity == nonASCIICaseVariant.identity, "non-ASCII case variants must share identity")

guard let shortLeft = FavoriteSongIdentity(title: "a", artist: "bc"),
      let shortRight = FavoriteSongIdentity(title: "ab", artist: "c")
else { fatalError("collision fixtures rejected") }
expect(shortLeft.storageKey != shortRight.storageKey, "length-prefixed storage keys must be collision-safe")

let retained = snapshot(
    title: "  A\tB  ",
    artist: "  Artist  Name ",
    albumName: "  Album  ",
    sourceChannel: source("channel-9", "  Nine  ", 9),
    savedAt: Date(timeIntervalSince1970: 42)
)
expect(retained.title == "A\tB", "title must retain trimmed original presentation")
expect(retained.artist == "Artist  Name", "artist must retain trimmed original presentation")
expect(retained.albumName == "Album", "verified album is optional trimmed context")
expect(retained.copyText == "Artist  Name — A\tB", "copy text must be exact saved artist-title projection")
expect(retained.sourceChannel.rawIdentity == "channel-9", "source identity must be retained as context")
expect(retained.sourceChannel.name == "Nine", "source name must be trimmed")
expect(retained.sourceChannel.displayNumber == 9, "source number must be retained")
expect(retained.savedAt == Date(timeIntervalSince1970: 42), "saved date must be retained")

let sameSongDifferentContext = snapshot(
    title: "A\tB",
    artist: "Artist  Name",
    albumName: "Another Album",
    sourceChannel: source("channel-99", "Other", 99)
)
expect(retained.identity == sameSongDifferentContext.identity, "album and source context must not alter identity")
expect(snapshot(albumName: "   ").albumName == nil, "blank album context must not persist")
expect(FavoriteSongSnapshot(title: "  ", artist: "Artist", sourceChannel: source()) == nil, "empty title must be rejected")
expect(FavoriteSongSnapshot(title: "Title", artist: "\n\t", sourceChannel: source()) == nil, "empty artist must be rejected")
expect(FavoriteSongSourceChannel(rawIdentity: "  ", name: nil, displayNumber: nil) == nil, "empty source identity must be rejected")

print("song favorite model contract: PASS")
