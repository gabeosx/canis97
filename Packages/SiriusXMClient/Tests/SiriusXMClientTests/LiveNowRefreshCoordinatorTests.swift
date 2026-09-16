import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Shared live metadata demand", .timeLimit(.minutes(1)))
struct LiveNowRefreshCoordinatorTests {
    @Test("The public client rejects an old legacy result after newer batch demand")
    func clientLegacyCompletion() async {
        let fetcher = ControlledLiveNowFetcher()
        let client = SiriusXMClient(metadataFetcher: fetcher)
        let legacy = Task { await client.metadata(for: LiveChannelID("a")) }
        await fetcher.waitForRequests(1)
        let batch = Task { await client.liveNow(for: ids("b")) }
        await fetcher.waitForRequests(2)
        await fetcher.release(1, result: result(ids("b")))
        #expect(await batch.value == result(ids("b")))
        await fetcher.release(0, result: result(ids("a")))
        #expect(await legacy.value == .failed(.superseded))
    }

    @Test("Client cancellation reaches the shared request and settles without an upstream response")
    func clientCancellation() async {
        let fetcher = ControlledLiveNowFetcher()
        let client = SiriusXMClient(metadataFetcher: fetcher)
        let batch = Task { await client.liveNow(for: ids("a")) }
        await fetcher.waitForRequests(1)
        batch.cancel()
        #expect(await batch.value == .failed(.cancelled))
        await fetcher.waitForCancellation(0)
        await fetcher.release(0, result: result(ids("a")))
    }

    @Test("Client reauthentication invalidates the shared owner before a late response")
    func clientReauthentication() async {
        let fetcher = ControlledLiveNowFetcher()
        let client = SiriusXMClient(metadataFetcher: fetcher)
        let batch = Task { await client.liveNow(for: ids("a")) }
        await fetcher.waitForRequests(1)
        #expect(await client.authenticate() == .waitingForAuthenticationComposition)
        #expect(await batch.value == .failed(.superseded))
        await fetcher.waitForCancellation(0)
        await fetcher.release(0, result: result(ids("a")))
    }

    @Test("Concurrent identical, reordered, subset, and repeated identities share one result")
    func sharedProjection() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let full = await coordinator.results(for: ids("a", "b", "missing"))
        await fetcher.waitForRequests(1)
        let identical = await coordinator.results(for: ids("a", "b", "missing"))
        let reordered = await coordinator.results(for: ids("b", "a"))
        let subset = await coordinator.results(for: ids("missing", "a", "a"))
        let empty = await coordinator.results(for: [])
        #expect(await fetcher.requests == [ids("a", "b", "missing")])
        await fetcher.release(0, result: result(ids("a", "b", "missing")))
        #expect(await first(full) == result(ids("a", "b", "missing")))
        #expect(await first(identical) == result(ids("a", "b", "missing")))
        #expect(await first(reordered) == result(ids("b", "a")))
        #expect(await first(subset) == result(ids("missing", "a", "a")))
        #expect(await first(empty) == result([]))
        #expect(await fetcher.requests.count == 1)
    }

    @Test("Completed snapshots are not cached; the next explicit demand replaces missing values")
    func noCompletedCache() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let firstDemand = await coordinator.results(for: ids("a"))
        await fetcher.waitForRequests(1)
        await fetcher.release(0, result: result(ids("a")))
        #expect(await first(firstDemand) == result(ids("a")))
        let next = await coordinator.results(for: ids("a"))
        await fetcher.waitForRequests(2)
        let absent = LiveNowAvailability.current(LiveNowSnapshot(observedAt: instant, channels: [LiveNowChannel(channelID: LiveChannelID("a"), state: .unavailable)]))
        await fetcher.release(1, result: absent)
        #expect(await first(next) == absent)
    }

    @Test("Expanded or disjoint coverage supersedes all old consumers and ignores late completion")
    func changedCoverage() async {
        for replacement in [ids("a", "b"), ids("b")] {
            let fetcher = ControlledLiveNowFetcher()
            let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
            let old = await coordinator.results(for: ids("a"))
            await fetcher.waitForRequests(1)
            let oldSibling = await coordinator.results(for: ids("a"))
            let new = await coordinator.results(for: replacement)
            #expect(await first(old) == .failed(.superseded))
            #expect(await first(oldSibling) == .failed(.superseded))
            await fetcher.waitForCancellation(0)
            await fetcher.waitForRequests(2)
            await fetcher.release(0, result: result(ids("a")))
            await fetcher.release(1, result: result(replacement))
            #expect(await first(new) == result(replacement))
            #expect(await fetcher.requests.count == 2)
        }
    }

    @Test("A cancelled consumer leaves shared work running for its sibling")
    func independentCancellation() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let stream = await coordinator.results(for: ids("a", "b"))
        await fetcher.waitForRequests(1)
        let sibling = await coordinator.results(for: ids("b"))
        let cancelled = Task { await first(stream) }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
        await fetcher.release(0, result: result(ids("a", "b")))
        #expect(await first(sibling) == result(ids("b")))
        #expect(await fetcher.cancellations.isEmpty)
        #expect(await fetcher.requests.count == 1)
    }

    @Test("Last-consumer cancellation returns promptly and cancels upstream without waiting for its response")
    func lastConsumerCancellation() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let demand = Task { await coordinator.refresh(for: ids("a")) }
        await fetcher.waitForRequests(1)
        demand.cancel()
        #expect(await demand.value == .failed(.cancelled))
        await fetcher.waitForCancellation(0)
        let next = await coordinator.results(for: ids("a"))
        await fetcher.waitForRequests(2)
        await fetcher.release(0, result: .failed(.notEntitled))
        await fetcher.release(1, result: result(ids("a")))
        #expect(await first(next) == result(ids("a")))
    }

    @Test("Already cancelled demand never starts work")
    func cancelledEntry() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let demand = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await coordinator.refresh(for: ids("a"))
        }
        #expect(await demand.value == .failed(.cancelled))
        #expect(await fetcher.requests.isEmpty)
    }

    @Test("Lifecycle invalidation settles every waiter before an uncooperative upstream responds")
    func invalidation() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let one = await coordinator.results(for: ids("a", "b"), context: 1)
        await fetcher.waitForRequests(1)
        let two = await coordinator.results(for: ids("b"), context: 1)
        await coordinator.invalidate(before: 2)
        #expect(await first(one) == .failed(.superseded))
        #expect(await first(two) == .failed(.superseded))
        await fetcher.waitForCancellation(0)
        let late = await coordinator.results(for: ids("a"), context: 1)
        #expect(await first(late) == .failed(.superseded))
        #expect(await fetcher.requests.count == 1)
        await fetcher.release(0, result: result(ids("a", "b")))
    }

    @Test("Older queued demand and invalidation cannot cancel a newer catalog generation")
    func delayedOldContext() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let current = await coordinator.results(for: ids("a"), context: 3)
        await fetcher.waitForRequests(1)
        let stale = await coordinator.results(for: ids("a"), context: 2)
        await coordinator.invalidate(before: 2)
        await coordinator.invalidate(before: 3)
        #expect(await first(stale) == .failed(.superseded))
        await fetcher.release(0, result: result(ids("a")))
        #expect(await first(current) == result(ids("a")))
        #expect(await fetcher.cancellations.isEmpty)
    }

    @Test("A new catalog generation cannot join an old request with identical coverage")
    func newContextSameCoverage() async {
        let fetcher = ControlledLiveNowFetcher()
        let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        let old = await coordinator.results(for: ids("a"), context: 1)
        await fetcher.waitForRequests(1)
        let current = await coordinator.results(for: ids("a"), context: 2)
        #expect(await first(old) == .failed(.superseded))
        await fetcher.waitForRequests(2)
        await fetcher.release(1, result: result(ids("a")))
        #expect(await first(current) == result(ids("a")))
        await fetcher.release(0, result: .failed(.authenticationUnavailable))
    }

    @Test("Closed failures fan out once and never trigger automatic retry")
    func failures() async {
        for failure: LiveNowFailure in [.authenticationUnavailable, .notEntitled, .networkUnavailable, .rateLimited, .protectedControl, .unsupportedResponse, .cancelled, .superseded] {
            let fetcher = ControlledLiveNowFetcher()
            let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
            let one = await coordinator.results(for: ids("a", "b"))
            await fetcher.waitForRequests(1)
            let two = await coordinator.results(for: ids("b"))
            await fetcher.release(0, result: .failed(failure))
            #expect(await first(one) == .failed(failure))
            #expect(await first(two) == .failed(failure))
            #expect(await fetcher.requests.count == 1)
        }
    }

    @Test("Malformed semantic snapshots cannot publish partial or contradictory projections")
    func malformedSemanticSeam() async {
        let requested = ids("a", "a", "b")
        let conflicting = LiveNowAvailability.current(LiveNowSnapshot(observedAt: instant, channels: [
            LiveNowChannel(channelID: LiveChannelID("a"), state: .unavailable),
            LiveNowChannel(channelID: LiveChannelID("a"), state: .unsupported),
            LiveNowChannel(channelID: LiveChannelID("b"), state: .unavailable),
        ]))
        for invalid in [result(ids("a")), result(ids("b", "a", "a")), conflicting] {
            let fetcher = ControlledLiveNowFetcher()
            let coordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
            let one = await coordinator.results(for: requested)
            await fetcher.waitForRequests(1)
            let two = await coordinator.results(for: ids("b"))
            await fetcher.release(0, result: invalid)
            #expect(await first(one) == .failed(.unsupportedResponse))
            #expect(await first(two) == .failed(.unsupportedResponse))
        }
    }

    @Test("Dropping the owner retires outstanding work and releases its consumers")
    func ownerLifetime() async {
        let fetcher = ControlledLiveNowFetcher()
        var owner: LiveNowRefreshCoordinator? = LiveNowRefreshCoordinator(fetcher: fetcher)
        let stream = await owner!.results(for: ids("a"))
        await fetcher.waitForRequests(1)
        owner = nil
        #expect(await first(stream) == .failed(.superseded))
        await fetcher.waitForCancellation(0)
        await fetcher.release(0, result: result(ids("a")))
    }
}

private let instant = Date(timeIntervalSince1970: 100)
private func ids(_ values: String...) -> [LiveChannelID] { values.map(LiveChannelID.init) }
private func result(_ ids: [LiveChannelID]) -> LiveNowAvailability {
    .current(LiveNowSnapshot(observedAt: instant, channels: ids.map {
        LiveNowChannel(channelID: $0, state: $0.rawValue == "missing" ? .unavailable : .current(LiveNowProgram(title: $0.rawValue, kind: .item, startedAt: instant)))
    }))
}
private func first(_ stream: AsyncStream<LiveNowAvailability>) async -> LiveNowAvailability? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

private actor ControlledLiveNowFetcher: LiveNowFetching, LiveMetadataFetching {
    private(set) var requests: [[LiveChannelID]] = []
    private(set) var cancellations: Set<Int> = []
    private var responses: [Int: CheckedContinuation<LiveNowAvailability, Never>] = [:]
    private var starts: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        let result = await liveNow(for: [channelID])
        guard case let .current(snapshot) = result,
              case let .current(program) = snapshot.channels.first?.state else { return .unavailable }
        return .current(MetadataSnapshot(channelID: channelID, program: LiveProgramMetadata(title: program.title, artist: program.artist)))
    }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }

    func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability {
        let index = requests.count
        requests.append(channelIDs)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                responses[index] = continuation
                let ready = starts.filter { $0.0 <= requests.count }
                starts.removeAll { $0.0 <= requests.count }
                for (_, waiter) in ready { waiter.resume() }
            }
        } onCancel: {
            Task { await self.recordCancellation(index) }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { starts.append((count, $0)) }
    }
    func waitForCancellation(_ index: Int) async {
        guard !cancellations.contains(index) else { return }
        await withCheckedContinuation { cancellationWaiters[index] = $0 }
    }
    private func recordCancellation(_ index: Int) {
        cancellations.insert(index)
        cancellationWaiters.removeValue(forKey: index)?.resume()
    }
    func release(_ index: Int, result: LiveNowAvailability) {
        responses.removeValue(forKey: index)?.resume(returning: result)
    }
}
