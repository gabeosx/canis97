import Foundation
import Observation

/// A demand-driven owner for live metadata scheduling. No media or credential
/// authority is exposed. Keep one monitor per app session and share its snapshot.
@MainActor @Observable
public final class LiveNowMonitor {
    /// The last full semantic replacement, retained through transient failures.
    public private(set) var snapshot: LiveNowSnapshot?
    /// The most recent closed failure; successful replacement clears it.
    public private(set) var failure: LiveNowFailure?
    /// Whether the current generation is awaiting a response.
    public private(set) var isRefreshing = false
    /// Whether a consumer has active demand for a nonempty catalog.
    public private(set) var isActive = false
    /// The earliest allowed next refresh, including manual refresh.
    public private(set) var nextRefreshAt: Date?
    private var channelIDs: [LiveChannelID] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    private var generation = 0
    private var consecutiveFailures = 0
    private let fetch: @Sendable ([LiveChannelID]) async -> LiveNowAvailability
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Creates an idle monitor. The closure should use the session’s shared client.
    public convenience init(refresh: @escaping @Sendable ([LiveChannelID]) async -> LiveNowAvailability) {
        self.init(refresh: refresh, now: { Date() }, sleep: { try await Task.sleep(for: .seconds($0)) })
    }

    init(refresh: @escaping @Sendable ([LiveChannelID]) async -> LiveNowAvailability,
         now: @escaping @Sendable () -> Date,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        fetch = refresh
        self.now = now
        self.sleep = sleep
    }

    deinit { worker?.cancel() }

    /// Supply the current entitled catalog and whether at least one feature
    /// needs updates. Changing catalog identities retires the previous snapshot,
    /// while the request budget and any closed failure survive until reset.
    public func setDemand(channelIDs: [LiveChannelID], active: Bool) {
        let changed = self.channelIDs != channelIDs
        let needed = active && !channelIDs.isEmpty
        guard changed || needed != isActive else { return }
        retire()
        self.channelIDs = channelIDs
        isActive = needed
        if changed {
            snapshot = nil
        }
        if needed && permitsAutomaticRefresh { start() }
    }

    /// A manual refresh respects the same request budget and backoff as automatic
    /// refresh. It cannot create a second in-flight operation or bypass cooldown.
    @discardableResult
    public func refresh() -> Bool {
        guard isActive, !isRefreshing,
              nextRefreshAt.map({ $0 <= now() }) ?? true else { return false }
        retire()
        start()
        return true
    }

    /// Clears all semantic state on session end and cancels work. A replacement
    /// waits for a cancellation-ignoring operation to drain before starting.
    public func reset() {
        retire()
        channelIDs = []
        isActive = false
        snapshot = nil
        failure = nil
        nextRefreshAt = nil
        consecutiveFailures = 0
    }

    /// Age is based on local observation time. Failures make retained results
    /// stale immediately; results older than five minutes must not look current.
    public func freshness(at date: Date) -> LiveNowFreshness {
        guard let snapshot else { return .unavailable }
        let age = date.timeIntervalSince(snapshot.observedAt)
        guard age >= 0, age < 300 else { return .unavailable }
        return failure != nil || age >= 90 ? .stale : .current
    }

    private var permitsAutomaticRefresh: Bool {
        switch failure {
        case nil, .networkUnavailable, .rateLimited, .superseded: true
        case .authenticationUnavailable, .notEntitled, .protectedControl, .unsupportedResponse, .cancelled: false
        }
    }

    private func retire() {
        generation &+= 1
        worker?.cancel()
        isRefreshing = false
    }

    private func start() {
        let expected = generation
        let previous = worker
        let fetch = fetch
        let now = now
        let sleep = sleep
        worker = Task { [weak self] in
            await previous?.value
            while !Task.isCancelled {
                guard self?.generation == expected, self?.isActive == true else { return }
                if let next = self?.nextRefreshAt, next > now() {
                    do { try await sleep(max(0, next.timeIntervalSince(now()))) }
                    catch { return }
                }
                guard !Task.isCancelled, self?.generation == expected,
                      let ids = self?.channelIDs else { return }
                self?.isRefreshing = true
                self?.nextRefreshAt = now().addingTimeInterval(60)
                let value = await fetch(ids)
                guard !Task.isCancelled, self?.generation == expected else { return }
                if self?.accept(value) != true { return }
            }
        }
    }

    private func accept(_ value: LiveNowAvailability) -> Bool {
        isRefreshing = false
        switch value {
        case let .current(snapshot):
            guard snapshot.channels.map(\.channelID) == channelIDs else {
                failure = .unsupportedResponse
                self.snapshot = nil
                worker = nil
                nextRefreshAt = now().addingTimeInterval(60)
                return false
            }
            self.snapshot = snapshot
            failure = nil
            consecutiveFailures = 0
            nextRefreshAt = now().addingTimeInterval(60)
        case let .failed(failure):
            self.failure = failure
            switch failure {
            case .networkUnavailable, .rateLimited, .superseded:
                consecutiveFailures = min(consecutiveFailures + 1, 4)
                let delay = min(60 * pow(2, Double(consecutiveFailures)), 300)
                nextRefreshAt = now().addingTimeInterval(delay)
            case .authenticationUnavailable, .notEntitled, .protectedControl, .unsupportedResponse, .cancelled:
                snapshot = nil
                nextRefreshAt = now().addingTimeInterval(60)
                worker = nil
                return false
            }
        }
        return true
    }
}

/// Display age of a local metadata observation, never playback availability.
public enum LiveNowFreshness: Sendable, Equatable {
    case current
    case stale
    case unavailable
}
