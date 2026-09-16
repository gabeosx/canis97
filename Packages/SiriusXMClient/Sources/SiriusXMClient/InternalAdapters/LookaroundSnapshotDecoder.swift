import Foundation

/// Receipt time is deliberately injected: no authoritative provider time has
/// been established for this operation. The opaque response marker is ignored.
protocol MetadataResponseObservationClock: Sendable {
    func now() -> Date
}

struct SystemMetadataResponseObservationClock: MetadataResponseObservationClock {
    func now() -> Date { Date() }
}

/// Short-lived adapter output. Batch callers receive only `availability`.
/// Artwork exists solely to preserve the selected-channel compatibility API.
struct DecodedLookaroundSnapshot: Sendable {
    let availability: LiveNowAvailability
    var artwork: [LiveChannelID: ChannelArtworkReference] = [:]

    func selectedChannel() -> MetadataAvailability {
        switch availability {
        case let .failed(failure):
            let legacyFailure: MetadataFailure = switch failure {
            case .authenticationUnavailable: .authenticationUnavailable
            case .notEntitled: .notEntitled
            case .superseded, .cancelled: .superseded
            default: .unsupportedResponse
            }
            return .failed(legacyFailure)
        case let .current(snapshot):
            guard let channel = snapshot.channels.first else { return .unavailable }
            switch channel.state {
            case .unavailable: return .unavailable
            case .unsupported: return .failed(.unsupportedResponse)
            case let .current(program):
                return .current(MetadataSnapshot(
                    channelID: channel.channelID,
                    program: LiveProgramMetadata(
                        title: program.title, artist: program.artist,
                        artwork: artwork[channel.channelID]
                    )
                ))
            }
        }
    }
}

/// Strict full-snapshot left join. Provider dictionaries never escape this file.
enum LookaroundSnapshotDecoder {
    static func decode(
        _ response: NativeTransportResponse,
        channelIDs: [LiveChannelID],
        observedAt: Date,
        includeArtwork: Bool = false
    ) -> DecodedLookaroundSnapshot {
        if let failure = response.transportFailure {
            return failed(failure == .cancelled ? .cancelled : .networkUnavailable)
        }
        guard response.redirectLocation == nil else { return failed(.protectedControl) }
        switch response.statusCode {
        case 401: return failed(.authenticationUnavailable)
        case 403: return failed(.notEntitled)
        case 429: return failed(.rateLimited)
        case 500 ... 599: return failed(.networkUnavailable)
        case 200 ... 299: break
        default: return failed(.unsupportedResponse)
        }
        let mediaType = response.contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mediaType == "application/json",
              response.body.count <= 8 * 1_024 * 1_024,
              observedAt.timeIntervalSince1970.isFinite,
              let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        else { return failed(.unsupportedResponse) }
        if root["bot"] as? Bool == true ||
            (root["challenge"] as? String).map({ ["captcha", "mfa", "control"].contains($0.lowercased()) }) == true {
            return failed(.protectedControl)
        }
        guard let channels = root["channels"] as? NSDictionary,
              channels.count <= 2_000,
              root["delta"] is String
        else { return failed(.unsupportedResponse) }
        if includeArtwork, let selectedChannelID = channelIDs.first {
            CompatibilitySchemaDiagnostics.recordLookaround(body: response.body, selectedChannelID: selectedChannelID)
        }

        // Identity equality intentionally follows LiveChannelID's exact scalar
        // semantics, rather than Swift String's canonical Unicode equivalence.
        var indexedChannels: [LiveChannelID: Any] = [:]
        for (key, value) in channels {
            guard let key = key as? String, !key.isEmpty else { continue }
            indexedChannels[LiveChannelID(key)] = value
        }
        let timestamps = Timestamps()
        var decoded: [LiveChannelID: ChannelResult] = [:]
        var artwork: [LiveChannelID: ChannelArtworkReference] = [:]
        let ordered = channelIDs.map { id in
            let result: ChannelResult
            if let existing = decoded[id] {
                result = existing
            } else if let value = indexedChannels[id] {
                result = decodeChannel(value, observedAt: observedAt, timestamps: timestamps, includeArtwork: includeArtwork)
                decoded[id] = result
            } else {
                result = ChannelResult(state: .unavailable)
            }
            artwork[id] = result.artwork
            return LiveNowChannel(channelID: id, state: result.state)
        }
        return DecodedLookaroundSnapshot(
            availability: .current(LiveNowSnapshot(observedAt: observedAt, channels: ordered)),
            artwork: artwork
        )
    }

    private struct ChannelResult {
        let state: LiveNowChannelState
        var artwork: ChannelArtworkReference? = nil
    }

    private static func decodeChannel(
        _ value: Any, observedAt: Date, timestamps: Timestamps, includeArtwork: Bool
    ) -> ChannelResult {
        guard let channel = value as? [String: Any],
              let cuts = channel["cuts"] as? [Any]
        else { return ChannelResult(state: .unsupported) }
        let current = select(cuts, kind: .item, observedAt: observedAt, timestamps: timestamps, includeArtwork: includeArtwork)
        // A valid item always wins, and malformed items cannot be hidden by a show.
        guard current.state == .unavailable else { return current }
        guard let shows = channel["shows"] else { return current }
        guard let shows = shows as? [Any] else { return ChannelResult(state: .unsupported) }
        return select(shows, kind: .show, observedAt: observedAt, timestamps: timestamps, includeArtwork: includeArtwork)
    }

    private static func select(
        _ values: [Any], kind: LiveNowContentKind, observedAt: Date,
        timestamps: Timestamps, includeArtwork: Bool
    ) -> ChannelResult {
        guard values.count <= 256 else { return ChannelResult(state: .unsupported) }
        var winner: LiveNowProgram?
        var winnerArtwork: ChannelArtworkReference?
        var conflicting = false
        for value in values {
            guard let item = value as? [String: Any],
                  let title = text(item["name"]),
                  let start = timestamps.parse(item["validFrom"]),
                  item["artistName"] == nil || item["artistName"] is NSNull || item["artistName"] is String
            else { return ChannelResult(state: .unsupported) }
            let artist = text(item["artistName"])
            if let rawArtist = item["artistName"] as? String,
               !rawArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, artist == nil {
                return ChannelResult(state: .unsupported)
            }
            guard start <= observedAt else { continue }
            let program = LiveNowProgram(title: title, artist: artist, kind: kind, startedAt: start)
            let artwork = includeArtwork ? LiveListeningAdapter.currentProgramArtworkReference(from: item) : nil
            if let prior = winner {
                if start < prior.startedAt { continue }
                if start == prior.startedAt {
                    if prior != program { conflicting = true }
                    // Inessential artwork disagreements never select arbitrarily.
                    if winnerArtwork != artwork { winnerArtwork = nil }
                    continue
                }
            }
            winner = program
            winnerArtwork = artwork
            conflicting = false
        }
        guard !conflicting else { return ChannelResult(state: .unsupported) }
        guard let winner else { return ChannelResult(state: .unavailable) }
        return ChannelResult(state: .current(winner), artwork: winnerArtwork)
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String, value.utf8.count <= 2_048 else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }

    private struct Timestamps {
        let ordinary = ISO8601DateFormatter()
        let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter
        }()

        func parse(_ value: Any?) -> Date? {
            guard let value = value as? String, value.utf8.count <= 64,
                  value.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})\z"#, options: .regularExpression) != nil
            else { return nil }
            // Foundation's ISO parser can normalize impossible calendar dates.
            // Validate the literal components before allowing that conversion.
            let parts = value.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
            guard parts.count == 6, parts[0] > 0, (1 ... 12).contains(parts[1]),
                  (0 ... 23).contains(parts[3]), (0 ... 59).contains(parts[4]), (0 ... 59).contains(parts[5])
            else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            guard let month = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)),
                  let days = calendar.range(of: .day, in: .month, for: month), days.contains(parts[2])
            else { return nil }
            if !value.hasSuffix("Z") {
                let offset = value.suffix(5).split(separator: ":").compactMap { Int($0) }
                guard offset.count == 2, offset[0] <= 23, offset[1] <= 59 else { return nil }
            }
            return ordinary.date(from: value) ?? fractional.date(from: value)
        }
    }

    private static func failed(_ failure: LiveNowFailure) -> DecodedLookaroundSnapshot {
        DecodedLookaroundSnapshot(availability: .failed(failure))
    }
}
