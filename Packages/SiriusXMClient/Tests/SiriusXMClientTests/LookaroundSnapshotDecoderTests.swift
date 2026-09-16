import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Strict bulk live metadata decoding")
struct LookaroundSnapshotDecoderTests {
    @Test("One full response joins requested identities in catalog order, including repeats and missing coverage")
    func orderedFullSnapshot() throws {
        let response = try lookaroundResponse([
            "b": ["cuts": [lookaroundCut("B")]],
            "a": ["cuts": [lookaroundCut("A")]],
            "unrequested": ["cuts": "malformed and ignored"],
        ])
        let snapshot = try snapshot(response, ids: ["b", "missing", "a", "b"])
        #expect(snapshot.observedAt == lookaroundObservation)
        #expect(snapshot.channels.map(\.channelID) == ["b", "missing", "a", "b"].map(LiveChannelID.init))
        #expect(snapshot.channels.map(\.state) == [current("B"), .unavailable, current("A"), current("B")])
    }

    @Test("All array permutations select the newest eligible cut and ignore future entries")
    func selectionIsIndependentOfArrayOrder() throws {
        let cuts = [lookaroundCut("Old", at: "2026-09-06T10:00:00Z"),
                    lookaroundCut("Current"), lookaroundCut("Future", at: "2026-09-06T13:00:00Z")]
        for order in [[0, 1, 2], [2, 1, 0], [1, 0, 2], [2, 0, 1], [1, 2, 0], [0, 2, 1]] {
            let response = try lookaroundResponse(["a": ["cuts": order.map { cuts[$0] }]])
            #expect(try snapshot(response).channels.first?.state == current("Current"))
            let legacy = LiveListeningAdapter.decodeMetadata(response, channelID: LiveChannelID("a"), observedAt: lookaroundObservation)
            guard case let .current(value) = legacy else { Issue.record("expected selected-channel projection"); continue }
            #expect(value.program?.title == "Current")
        }
    }

    @Test("Empty and future-only channels have no current metadata")
    func unavailableCoverage() throws {
        for cuts in [[], [lookaroundCut("Future", at: "2026-09-06T12:00:00.001Z")]] {
            #expect(try snapshot(lookaroundResponse(["a": ["cuts": cuts]])).channels.first?.state == .unavailable)
        }
    }

    @Test("Ordinary, fractional, and offset timestamps share one reference instant")
    func timestampForms() throws {
        for date in ["2026-09-06T12:00:00Z", "2026-09-06T12:00:00.000Z", "2026-09-06T08:00:00-04:00"] {
            let state = try snapshot(lookaroundResponse(["a": ["cuts": [lookaroundCut("Now", at: date)]]])).channels[0].state
            #expect(state == .current(LiveNowProgram(title: "Now", kind: .item, startedAt: lookaroundObservation)))
        }
        let response = try lookaroundResponse(["a": ["cuts": [
            lookaroundCut("Earlier", at: "2026-09-06T11:00:00Z"),
            lookaroundCut("Fractional", at: "2026-09-06T11:00:00.123Z")
        ]]])
        guard case let .current(program) = try snapshot(response).channels[0].state else { Issue.record("expected fractional winner"); return }
        #expect(program.title == "Fractional")
        #expect(abs(program.startedAt.timeIntervalSince(lookaroundObservation) + 3599.877) < 0.001)
    }

    @Test("Nonmusic artist text is optional and is never used to infer music")
    func optionalArtist() throws {
        for artist: Any? in [nil, NSNull(), "", "  ", " Synthetic Host "] {
            var cut = lookaroundCut(" Talk Program ")
            cut["artistName"] = artist
            let state = try snapshot(lookaroundResponse(["a": ["cuts": [cut]]])).channels[0].state
            #expect(state == current("Talk Program", artist: (artist as? String)?.contains("Host") == true ? "Synthetic Host" : nil))
        }
    }

    @Test("Only eligible named shows provide fallback; valid items always take precedence")
    func showFallback() throws {
        let show = lookaroundCut("The Show", at: "2026-09-06T10:00:00Z")
        let response = try lookaroundResponse([
            "show": ["cuts": [], "shows": [show]],
            "cut": ["cuts": [lookaroundCut("The Item")], "shows": [show]],
            "future": ["cuts": [], "shows": [lookaroundCut("Future Show", at: "2026-09-06T13:00:00Z")]],
            "bad-show": ["cuts": [], "shows": [["name": "", "validFrom": "invalid"]]],
            "ignore-show": ["cuts": [lookaroundCut("The Item")], "shows": "unknown shape"],
            "bad-cut": ["cuts": [[:]], "shows": [show]],
        ])
        let results = try snapshot(response, ids: ["show", "cut", "future", "bad-show", "ignore-show", "bad-cut"]).channels.map(\.state)
        #expect(results == [
            .current(LiveNowProgram(title: "The Show", kind: .show, startedAt: lookaroundObservation.addingTimeInterval(-7200))),
            current("The Item"), .unavailable, .unsupported, current("The Item"), .unsupported
        ])
    }

    @Test("Semantic duplicates collapse; only conflicting candidates at the winning timestamp close the channel")
    func duplicatesAndConflicts() throws {
        let a = lookaroundCut("Same")
        var duplicate = a
        duplicate["unknown"] = ["ignored": "data"]
        duplicate["name"] = " Same "
        #expect(try snapshot(lookaroundResponse(["a": ["cuts": [a, duplicate, a]]])).channels[0].state == current("Same"))
        for conflict in [lookaroundCut("Other"), lookaroundCut("Same", artist: "Other Artist")] {
            for cuts in [[a, conflict], [conflict, a], [a, conflict, a]] {
                #expect(try snapshot(lookaroundResponse(["a": ["cuts": cuts]])).channels[0].state == .unsupported)
            }
            let later = lookaroundCut("Newer", at: "2026-09-06T11:30:00Z")
            for cuts in [[a, conflict, later], [a, later, conflict], [later, a, conflict], [conflict, a, later], [conflict, later, a], [later, conflict, a]] {
                #expect(try snapshot(lookaroundResponse(["a": ["cuts": cuts]])).channels[0].state ==
                    .current(LiveNowProgram(title: "Newer", kind: .item, startedAt: lookaroundObservation.addingTimeInterval(-1800))))
            }
        }
    }

    @Test("Malformed requested data is contained; a valid sibling survives")
    func malformedChannels() throws {
        let invalid: [Any] = [NSNull(), [], "wrong", [:], ["cuts": "wrong"], ["cuts": [NSNull()]],
            ["cuts": [["name": "Missing timestamp"]]], ["cuts": [lookaroundCut("Bad", at: "not-a-date")]],
            ["cuts": [lookaroundCut("Bad", at: "2026-09-06T11:00:00Zjunk")]],
            ["cuts": [["name": 7, "validFrom": "2026-09-06T11:00:00Z"]]],
            ["cuts": [["name": "Bad", "artistName": [:], "validFrom": "2026-09-06T11:00:00Z"]]],
            ["cuts": [lookaroundCut(String(repeating: "a", count: 2049))]],
            ["cuts": [lookaroundCut("Bad\u{0000}text")]], ["cuts": [], "shows": NSNull()]]
        for value in invalid {
            let response = try lookaroundResponse(["a": value, "b": ["cuts": [lookaroundCut("Good")]]])
            #expect(try snapshot(response, ids: ["a", "b"]).channels.map(\.state) == [.unsupported, current("Good")])
        }
    }

    @Test("Root, channels, and marker structure are mandatory even with empty demand")
    func malformedRoots() throws {
        let invalid: [Any] = [[], ["channels": []], [:], ["channels": [:]],
            ["channels": [:], "delta": NSNull()], ["channels": [:], "delta": [:]],
            ["channels": [:], "delta": 42], ["channels": NSNull(), "delta": ""],
            ["channels": [], "delta": ""], ["channels": "wrong", "delta": ""]]
        for root in invalid {
            let response = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: try JSONSerialization.data(withJSONObject: root))
            #expect(LookaroundSnapshotDecoder.decode(response, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.unsupportedResponse))
        }
        let brokenJSON = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data("{".utf8))
        #expect(LookaroundSnapshotDecoder.decode(brokenJSON, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.unsupportedResponse))
    }

    @Test("Unknown fields and opaque marker values are discarded, never treated as patches or clocks")
    func unknownFieldsAndReplacement() throws {
        let first = try lookaroundResponse(["a": ["cuts": [lookaroundCut("Old")]]], delta: "opaque-marker")
        let second = try lookaroundResponse([:], delta: "2020-01-01T00:00:00Z")
        #expect(try snapshot(first).channels[0].state == current("Old"))
        #expect(try snapshot(second).channels[0].state == .unavailable)
        #expect(try snapshot(second).observedAt == lookaroundObservation)
    }

    @Test("Transport and authorization failures remain closed")
    func closedFailures() throws {
        let body = try lookaroundResponse([:]).body
        for (status, failure): (Int, LiveNowFailure) in [(401, .authenticationUnavailable), (403, .notEntitled), (429, .rateLimited), (503, .networkUnavailable), (404, .unsupportedResponse)] {
            let response = NativeTransportResponse(statusCode: status, contentType: "application/json", body: body)
            #expect(LookaroundSnapshotDecoder.decode(response, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(failure))
        }
        for contentType in ["text/html", "application/json-invalid", ""] {
            let response = NativeTransportResponse(statusCode: 200, contentType: contentType, body: body)
            #expect(LookaroundSnapshotDecoder.decode(response, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.unsupportedResponse))
        }
        let cancelled = NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailure: .cancelled)
        #expect(LookaroundSnapshotDecoder.decode(cancelled, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.cancelled))
    }

    @Test("Impossible calendar dates and malformed clock components are not normalized into current programs")
    func invalidCalendarDates() throws {
        for date in ["2026-02-30T11:00:00Z", "2026-02-29T11:00:00Z", "2026-04-31T11:00:00Z",
                     "2026-00-01T11:00:00Z", "2026-09-00T11:00:00Z", "2026-09-06T24:00:00Z",
                     "2026-09-06T11:60:00Z", "2026-09-06T11:00:99Z", "2026-09-06T11:00:00+99:99",
                     "2026-09-06", "2026-09-06T11:00:00", "2026-09-06T11:00:00Z\n"] {
            let response = try lookaroundResponse(["a": ["cuts": [lookaroundCut("Invalid", at: date)]]])
            #expect(try snapshot(response).channels[0].state == .unsupported, "Rejected timestamp: \(date)")
        }
        let leap = try lookaroundResponse(["a": ["cuts": [lookaroundCut("Leap Day", at: "2024-02-29T11:00:00Z")]]])
        guard case .current = try snapshot(leap).channels[0].state else { Issue.record("valid leap day rejected"); return }
    }

    @Test("Opaque catalog identities are not matched by Unicode normalization")
    func exactIdentityJoin() throws {
        let response = try lookaroundResponse(["caf\u{00e9}": ["cuts": [lookaroundCut("A")]]])
        let value = try snapshot(response, ids: ["cafe\u{0301}", "caf\u{00e9}"])
        #expect(value.channels.map(\.state) == [.unavailable, current("A")])
    }

    @Test("Oversized collections and text fail within their defined boundary")
    func boundedDecoding() throws {
        let response = try lookaroundResponse([
            "a": ["cuts": Array(repeating: lookaroundCut("Too many"), count: 257)],
            "b": ["cuts": [lookaroundCut("Good")]],
        ])
        #expect(try snapshot(response, ids: ["a", "b"]).channels.map(\.state) == [.unsupported, current("Good")])
        let oversized = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 1))
        #expect(LookaroundSnapshotDecoder.decode(oversized, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.unsupportedResponse))
        let tooManyChannels = try lookaroundResponse(Dictionary(uniqueKeysWithValues: (0 ... 2_000).map { ("channel-\($0)", ["cuts": []]) }))
        #expect(LookaroundSnapshotDecoder.decode(tooManyChannels, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.unsupportedResponse))
    }

    @Test("Protected controls and redirects cannot be disguised by a valid root")
    func protectedControls() throws {
        for control: [String: Any] in [["bot": true], ["challenge": "captcha"], ["challenge": "mfa"], ["challenge": "control"]] {
            var root: [String: Any] = ["channels": [:], "delta": ""]
            root.merge(control) { _, new in new }
            let response = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: try JSONSerialization.data(withJSONObject: root))
            #expect(LookaroundSnapshotDecoder.decode(response, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.protectedControl))
        }
        let redirect = NativeTransportResponse(statusCode: 200, contentType: "application/json", body: try lookaroundResponse([:]).body, redirectLocation: "https://fixture.invalid")
        #expect(LookaroundSnapshotDecoder.decode(redirect, channelIDs: [], observedAt: lookaroundObservation).availability == .failed(.protectedControl))
    }

    private func snapshot(_ response: NativeTransportResponse, ids: [String] = ["a"]) throws -> LiveNowSnapshot {
        let result = LookaroundSnapshotDecoder.decode(response, channelIDs: ids.map(LiveChannelID.init), observedAt: lookaroundObservation)
        guard case let .current(snapshot) = result.availability else {
            Issue.record("expected full snapshot"); throw FixtureFailure.unexpectedFailure
        }
        #expect(result.artwork.isEmpty)
        return snapshot
    }

    private func current(_ title: String, artist: String? = nil) -> LiveNowChannelState {
        .current(LiveNowProgram(title: title, artist: artist, kind: .item, startedAt: lookaroundObservation.addingTimeInterval(-3600)))
    }

    private enum FixtureFailure: Error { case unexpectedFailure }
}

let lookaroundObservation = Date(timeIntervalSince1970: 1_788_696_000) // 2026-09-06 12:00 UTC

func lookaroundCut(_ title: String, at: String = "2026-09-06T11:00:00Z", artist: String? = nil) -> [String: Any] {
    var result: [String: Any] = ["name": title, "validFrom": at, "isAd": false]
    result["artistName"] = artist
    return result
}

func lookaroundResponse(_ channels: [String: Any], delta: String = "") throws -> NativeTransportResponse {
    NativeTransportResponse(statusCode: 200, contentType: "application/json; charset=utf-8", body: try JSONSerialization.data(withJSONObject: [
        "channels": channels, "delta": delta, "unknown": ["ignored": true]
    ]))
}
