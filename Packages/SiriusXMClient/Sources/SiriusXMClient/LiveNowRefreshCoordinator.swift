import Foundation

/// Shares explicit metadata demand. Only semantic inputs/results cross this
/// coordinator; it owns neither credentials nor a timer nor a completed cache.
actor LiveNowRefreshCoordinator {
    private struct Consumer: Sendable {
        let channelIDs: [LiveChannelID]
        let continuation: AsyncStream<LiveNowAvailability>.Continuation
    }

    private struct Refresh: Sendable {
        let id: UUID
        let context: Int
        let channelIDs: [LiveChannelID]
        let coverage: Set<LiveChannelID>
        let task: Task<Void, Never>
        var consumers: [UUID: Consumer]
    }

    private let fetcher: any LiveNowFetching
    private var pending: Refresh?
    private var latestContext = 0

    init(fetcher: any LiveNowFetching) { self.fetcher = fetcher }

    func refresh(for channelIDs: [LiveChannelID], context: Int = 0) async -> LiveNowAvailability {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        let results = results(for: channelIDs, context: context)
        for await result in results {
            return Task.isCancelled ? .failed(.cancelled) : result
        }
        return .failed(.cancelled)
    }

    /// One bounded result per consumer. Registering is synchronous on this actor,
    /// so each demand either joins the current coverage or replaces it atomically.
    /// Kept internal to make demand ownership and cancellation independently testable.
    func results(for channelIDs: [LiveChannelID], context: Int = 0) -> AsyncStream<LiveNowAvailability> {
        let consumerID = UUID()
        let (stream, continuation) = AsyncStream<LiveNowAvailability>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard context >= latestContext else {
            continuation.yield(.failed(.superseded))
            continuation.finish()
            return stream
        }
        latestContext = context
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                Task { await self?.cancel(consumerID: consumerID) }
            }
        }
        let consumer = Consumer(channelIDs: channelIDs, continuation: continuation)
        if let pending, pending.context == context, Set(channelIDs).isSubset(of: pending.coverage) {
            self.pending?.consumers[consumerID] = consumer
            return stream
        }

        invalidate()
        let id = UUID()
        let task = Task { [fetcher, weak self] in
            guard !Task.isCancelled else { return }
            let result = await fetcher.liveNow(for: channelIDs)
            await self?.complete(id: id, result: result)
        }
        pending = Refresh(id: id, context: context, channelIDs: channelIDs, coverage: Set(channelIDs), task: task, consumers: [consumerID: consumer])
        return stream
    }

    func invalidate() {
        guard let retired = pending else { return }
        pending = nil
        retired.task.cancel()
        for consumer in retired.consumers.values {
            consumer.continuation.yield(.failed(.superseded))
            consumer.continuation.finish()
        }
    }

    /// Retire only work from an older client lifecycle. A delayed invalidation
    /// must neither cancel newer demand nor admit a delayed older registration.
    func invalidate(before context: Int) {
        guard context >= latestContext else { return }
        latestContext = context
        if let pending, pending.context < context { invalidate() }
    }

    private func cancel(consumerID: UUID) {
        guard pending?.consumers.removeValue(forKey: consumerID) != nil else { return }
        if pending?.consumers.isEmpty == true {
            pending?.task.cancel()
            pending = nil
        }
    }

    private func complete(id: UUID, result: LiveNowAvailability) {
        guard let completed = pending, completed.id == id else { return }
        pending = nil
        // Validate the semantic seam before projecting to subsets. There is no
        // partially published snapshot and no arbitrary choice for duplicates.
        var states: [LiveChannelID: LiveNowChannelState] = [:]
        var failure: LiveNowFailure?
        var observedAt: Date?
        switch result {
        case let .failed(reason): failure = reason
        case let .current(snapshot):
            guard snapshot.channels.map(\.channelID) == completed.channelIDs else {
                finish(completed, with: .failed(.unsupportedResponse))
                return
            }
            for channel in snapshot.channels {
                if let previous = states[channel.channelID], previous != channel.state {
                    finish(completed, with: .failed(.unsupportedResponse))
                    return
                }
                states[channel.channelID] = channel.state
            }
            observedAt = snapshot.observedAt
        }

        for consumer in completed.consumers.values {
            let value: LiveNowAvailability
            if let failure {
                value = .failed(failure)
            } else if let observedAt {
                value = .current(LiveNowSnapshot(observedAt: observedAt, channels: consumer.channelIDs.map {
                    LiveNowChannel(channelID: $0, state: states[$0] ?? .unavailable)
                }))
            } else {
                value = .failed(.unsupportedResponse)
            }
            consumer.continuation.yield(value)
            consumer.continuation.finish()
        }
    }

    private nonisolated func finish(_ refresh: Refresh, with result: LiveNowAvailability) {
        for consumer in refresh.consumers.values {
            consumer.continuation.yield(result)
            consumer.continuation.finish()
        }
    }

    deinit {
        pending?.task.cancel()
        if let pending { finish(pending, with: .failed(.superseded)) }
    }
}
