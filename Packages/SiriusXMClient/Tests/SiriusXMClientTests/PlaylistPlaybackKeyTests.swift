import Foundation
import Testing
@_spi(Playback) @testable import SiriusXMClient

@Suite("Playlist-selected playback keys", .timeLimit(.minutes(1)))
struct PlaylistPlaybackKeyTests {
    @Test("Key responses must match the requested identity and contain exactly sixteen bytes")
    func validatesKeyIdentityAndBytes() throws {
        let id = "00000000-0000-0000-0000-000000000001"
        let expected = try keyID(1)
        let other = try keyID(2)
        for length in [0, 1, 15, 16, 17, 32] {
            let bytes = Data(repeating: 0, count: length)
            let body = try JSONSerialization.data(withJSONObject: ["keyId": id, "key": bytes.base64EncodedString()])
            #expect(FixedLivePlaybackKeyData.decode(body, matching: expected) == (length == 16 ? bytes : nil))
            #expect(FixedLivePlaybackKeyData.decode(body, matching: other) == nil)
        }
        #expect(FixedLivePlaybackKeyData.decode(Data("not JSON".utf8), matching: expected) == nil)
    }

    @Test("Key delivery honors byte ranges, end-of-file, and all-data requests without overflow")
    func keyDataRanges() {
        let data = Data(0..<16)
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 0, length: 16, allToEnd: false) == data)
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 8, length: 4, allToEnd: false) == Data(8..<12))
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 8, length: Int.max, allToEnd: false) == Data(8..<16))
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 8, length: 0, allToEnd: true) == Data(8..<16))
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 16, length: 1, allToEnd: false) == Data())
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: -1, length: 16, allToEnd: false) == nil)
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: Int64.max, length: 16, allToEnd: false) == nil)
        #expect(FixedLivePlaybackKeyData.chunk(data, offset: 0, length: -1, allToEnd: false) == nil)
    }

    @Test("Media errors preserve the precise key failure without provider data", arguments: [
        LiveStreamResolutionFailure.authenticationUnavailable, .entitlementUnavailable,
        .protectedControl, .networkUnavailable, .unsupportedProtection, .cancelled, .superseded,
    ])
    func preciseFailures(_ failure: LiveStreamResolutionFailure) async throws {
        let source = FixedLivePlaybackKeySource(initialID: try keyID(1), initialKey: Data([1]),
            isCurrent: { true }, authorize: { _ in .failed(failure) })
        let selected = try keyID(2)
        #expect(await source.key(for: selected) == .failed(failure))
        let error = SiriusXMPlaybackError.error(for: failure)
        #expect(SiriusXMPlaybackError.resolutionFailure(from: error) == failure)
        #expect(error.userInfo.isEmpty)
        #expect(SiriusXMPlaybackError.resolutionFailure(from: NSError(domain: "unrecognized", code: error.code)) == nil)
        #expect(SiriusXMPlaybackError.resolutionFailure(from: NSError(domain: error.domain, code: 999)) == nil)
    }

    @Test("Only the observed fixed HTTPS key endpoint admits a playlist key")
    func closedKeyEndpoint() throws {
        let id = "00000000-0000-0000-0000-000000000001"
        let base = "https://api.edge-gateway.siriusxm.com/playback/key/v1/\(id)"
        #expect(FixedLivePlaybackKeyID.playlistKey(from: URL(string: base)!) != nil)
        for value in [
            base.replacingOccurrences(of: "https:", with: "http:"),
            base.replacingOccurrences(of: "api.edge-gateway.siriusxm.com", with: "attacker.invalid"),
            base.replacingOccurrences(of: ".com/", with: ".com.attacker.invalid/"),
            base.replacingOccurrences(of: ".com/", with: ".com:443/"),
            base.replacingOccurrences(of: "https://", with: "https://user:password@"),
            base + "?token=synthetic", base + "#fragment", base + "/extra",
            base.replacingOccurrences(of: id, with: "not-a-uuid"),
            base.replacingOccurrences(of: "/v1/", with: "/v2/"),
            base.replacingOccurrences(of: id, with: "%2F" + id),
        ] {
            #expect(FixedLivePlaybackKeyID.playlistKey(from: URL(string: value)!) == nil)
        }
    }

    @Test("The playlist can authorize a different key from tuneSource and reuse only its matching bytes")
    func playlistKeyDiffersFromTuneKey() async throws {
        let initial = try keyID(1), selected = try keyID(2)
        let recorder = KeyRecorder()
        let source = FixedLivePlaybackKeySource(initialID: initial, initialKey: Data([1]),
            isCurrent: { true }, authorize: { await recorder.load($0) })
        #expect(await source.key(for: initial) == .authorized(Data([1])))
        #expect(await source.key(for: selected) == .authorized(Data([2])))
        #expect(await source.key(for: selected) == .authorized(Data([2])))
        #expect(await recorder.requests == [selected])
    }

    @Test("Concurrent key loads share matching work and serialize different keys")
    func serializedAndCoalesced() async throws {
        let a = try keyID(1), b = try keyID(2), c = try keyID(3)
        let gate = KeyGate()
        let source = FixedLivePlaybackKeySource(initialID: a, initialKey: Data([1]),
            isCurrent: { true }, authorize: { await gate.load($0) })
        let first = Task { await source.key(for: b) }
        await gate.waitForRequests(1)
        let duplicate = Task { await source.key(for: b) }
        let next = Task { await source.key(for: c) }
        await gate.release(b, Data([2]))
        await gate.waitForRequests(2)
        await gate.release(c, Data([3]))
        #expect(await first.value == .authorized(Data([2])))
        #expect(await duplicate.value == .authorized(Data([2])))
        #expect(await next.value == .authorized(Data([3])))
        #expect(await gate.requests == [b, c])
        #expect(await gate.maximumInFlight == 1)
    }

    @Test("Denial fails closed without retrying or falling back to the tune key")
    func rejectedKeyNeverFallsBack() async throws {
        let a = try keyID(1), b = try keyID(2), c = try keyID(3)
        let recorder = KeyRecorder(denied: b)
        let source = FixedLivePlaybackKeySource(initialID: a, initialKey: Data([1]),
            isCurrent: { true }, authorize: { await recorder.load($0) })
        #expect(await source.key(for: b) == .failed(.entitlementUnavailable))
        #expect(await source.key(for: b) == .failed(.entitlementUnavailable))
        #expect(await source.key(for: a) == .failed(.entitlementUnavailable))
        #expect(await source.key(for: c) == .failed(.entitlementUnavailable))
        #expect(await recorder.requests == [b])
    }

    @Test("Session retirement rejects late bytes and cached keys")
    func retiredSessionCannotPublish() async throws {
        let a = try keyID(1), b = try keyID(2)
        let gate = KeyGate()
        let source = FixedLivePlaybackKeySource(initialID: a, initialKey: Data([1]),
            isCurrent: { await gate.isCurrent }, authorize: { await gate.load($0) })
        let request = Task { await source.key(for: b) }
        await gate.waitForRequests(1)
        await gate.retire()
        await gate.release(b, Data([2]))
        #expect(await request.value == .failed(.superseded))
        #expect(await source.key(for: a) == .failed(.superseded))
        #expect(await source.key(for: b) == .failed(.superseded))
    }

    @Test("Continuous key changes retain only four cached entries")
    func boundedCache() async throws {
        let recorder = KeyRecorder()
        let initial = try keyID(1)
        let source = FixedLivePlaybackKeySource(initialID: initial, initialKey: Data([1]),
            isCurrent: { true }, authorize: { await recorder.load($0) })
        for index in 2...8 {
            let id = try keyID(index)
            #expect(await source.key(for: id) == .authorized(Data([2])))
        }
        #expect(await source.key(for: initial) == .authorized(Data([2])))
        #expect(await recorder.requests.count == 8)
    }

    @Test("A cancelled loading request cannot publish late authorized bytes")
    func cancelledRequestRejectsLateCompletion() async throws {
        let a = try keyID(1), b = try keyID(2)
        let gate = KeyGate()
        let source = FixedLivePlaybackKeySource(initialID: a, initialKey: Data([1]),
            isCurrent: { true }, authorize: { await gate.load($0) })
        let request = Task { await source.key(for: b) }
        await gate.waitForRequests(1)
        request.cancel()
        await gate.release(b, Data([2]))
        #expect(await request.value == .failed(.cancelled))
    }

    @Test("Cancellation during the session check also rejects a cached key")
    func cancellationDuringLeaseCheck() async throws {
        let a = try keyID(1)
        let lease = KeyLeaseGate()
        let source = FixedLivePlaybackKeySource(initialID: a, initialKey: Data([1]),
            isCurrent: { await lease.check() }, authorize: { _ in .failed(.unsupportedProtection) })
        let request = Task { await source.key(for: a) }
        await lease.waitUntilChecking()
        request.cancel()
        await lease.release()
        #expect(await request.value == .failed(.cancelled))
    }
}

private func keyID(_ index: Int) throws -> FixedLivePlaybackKeyID {
    try #require(FixedLivePlaybackKeyID.playlistKey(from: URL(string:
        "https://api.edge-gateway.siriusxm.com/playback/key/v1/00000000-0000-0000-0000-\(String(format: "%012d", index))")!))
}

private actor KeyRecorder {
    let denied: FixedLivePlaybackKeyID?
    private(set) var requests: [FixedLivePlaybackKeyID] = []
    init(denied: FixedLivePlaybackKeyID? = nil) { self.denied = denied }
    func load(_ id: FixedLivePlaybackKeyID) -> FixedLivePlaybackKeyResult {
        requests.append(id)
        return id == denied ? .failed(.entitlementUnavailable) : .authorized(Data([2]))
    }
}

private actor KeyGate {
    private(set) var requests: [FixedLivePlaybackKeyID] = []
    private(set) var maximumInFlight = 0
    private(set) var isCurrent = true
    private var pending: [FixedLivePlaybackKeyID: CheckedContinuation<FixedLivePlaybackKeyResult, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func load(_ id: FixedLivePlaybackKeyID) async -> FixedLivePlaybackKeyResult {
        requests.append(id)
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            maximumInFlight = max(maximumInFlight, pending.count)
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func release(_ id: FixedLivePlaybackKeyID, _ data: Data) {
        pending.removeValue(forKey: id)!.resume(returning: .authorized(data))
    }
    func retire() { isCurrent = false }
}

private actor KeyLeaseGate {
    private var checking = false
    private var started: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<Bool, Never>?
    func check() async -> Bool {
        checking = true
        return await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilChecking() async {
        guard !checking else { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { result?.resume(returning: true); result = nil }
}
