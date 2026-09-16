import Foundation
import Observation
import Synchronization
import Testing
@testable import SiriusXMClient

@Suite("Demand-driven metadata scheduling", .timeLimit(.minutes(1)))
@MainActor
struct LiveNowMonitorTests {
    @Test("One shared demand refreshes immediately, then respects a 60-second budget")
    func cadence() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: false)
        #expect(!monitor.isActive)
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        monitor.setDemand(channelIDs: driver.ids, active: true)
        #expect(!monitor.refresh())
        driver.finish(0, with: driver.snapshot())
        await driver.waitForSleeps(1)
        #expect(driver.delays == [60])
        #expect(!monitor.refresh())
        #expect(monitor.snapshot?.channels.map(\.channelID) == driver.ids)
        driver.wake(0, advancing: 60)
        await driver.waitForRequests(2)
        #expect(driver.requests == [driver.ids, driver.ids])
        driver.finish(1, with: driver.snapshot(missing: true))
        await driver.waitForSleeps(2)
        #expect(monitor.snapshot?.channels.allSatisfy { $0.state == .unavailable } == true)
        monitor.reset()
    }

    @Test("Transient failures retain stale data and back off to a five-minute ceiling")
    func backoff() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: driver.snapshot())
        await driver.waitForSleeps(1)
        driver.wake(0, advancing: 60)
        for (index, delay) in [120.0, 240, 300, 300, 300].enumerated() {
            await driver.waitForRequests(index + 2)
            driver.finish(index + 1, with: .failed(index.isMultiple(of: 2) ? .networkUnavailable : .rateLimited))
            await driver.waitForSleeps(index + 2)
            #expect(driver.delays[index + 1] == delay)
            #expect(!monitor.refresh())
            #expect(monitor.snapshot != nil)
            if index == 0 { #expect(monitor.freshness(at: driver.clock.now) == .stale) }
            driver.wake(index + 1, advancing: delay)
        }
        await driver.waitForRequests(7)
        driver.finish(6, with: driver.snapshot())
        await driver.waitForSleeps(7)
        #expect(driver.delays.last == 60)
        #expect(monitor.failure == nil)
        #expect(monitor.freshness(at: driver.clock.now) == .current)
        monitor.reset()
    }

    @Test("Demand pauses cancel work; returning consumers cannot bypass the cooldown")
    func pauseResume() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: driver.snapshot())
        await driver.waitForSleeps(1)
        monitor.setDemand(channelIDs: driver.ids, active: false)
        #expect(!monitor.isActive)
        #expect(!monitor.refresh())
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForSleeps(2)
        #expect(driver.requests.count == 1)
        #expect(driver.delays == [60, 60])
        driver.wake(1, advancing: 60)
        await driver.waitForRequests(2)
        monitor.reset()
        driver.finish(1, with: driver.snapshot())
        #expect(monitor.snapshot == nil)
        #expect(!monitor.isRefreshing)
        #expect(monitor.nextRefreshAt == nil)
    }

    @Test("A replacement catalog retains transient backoff and clears old semantic data")
    func catalogBackoff() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: .failed(.rateLimited))
        await driver.waitForSleeps(1)
        let replacement = [LiveChannelID("replacement")]
        monitor.setDemand(channelIDs: replacement, active: true)
        await driver.waitForSleeps(2)
        #expect(driver.delays == [120, 120])
        #expect(driver.requests.count == 1)
        #expect(monitor.snapshot == nil)
        #expect(!monitor.refresh())
        driver.wake(1, advancing: 120)
        await driver.waitForRequests(2)
        driver.finish(1, with: driver.snapshot(ids: replacement))
        await driver.waitForSleeps(3)
        #expect(monitor.failure == nil)
        monitor.reset()
    }

    @Test("Old catalog and session completions cannot publish after replacement or reset")
    func generations() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        let replacement = [LiveChannelID("replacement")]
        monitor.setDemand(channelIDs: replacement, active: true)
        #expect(driver.requests.count == 1)
        driver.finish(0, with: driver.snapshot())
        await driver.waitForSleeps(1)
        #expect(monitor.snapshot == nil)
        driver.wake(0, advancing: 60)
        await driver.waitForRequests(2)
        driver.finish(1, with: driver.snapshot(ids: replacement))
        await driver.waitForSleeps(2)
        #expect(monitor.snapshot?.channels.map(\.channelID) == replacement)
        monitor.reset()
        #expect(monitor.snapshot == nil)
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(3)
        monitor.reset()
        driver.finish(2, with: driver.snapshot())
        monitor.setDemand(channelIDs: replacement, active: true)
        await driver.waitForRequests(4)
        driver.finish(3, with: driver.snapshot(ids: replacement))
        await driver.waitForSleeps(3)
        #expect(monitor.snapshot?.channels.map(\.channelID) == replacement)
        monitor.reset()
    }

    @Test("Closed failures stop automatic requests even after visibility changes", arguments: [LiveNowFailure.authenticationUnavailable, .notEntitled, .protectedControl, .unsupportedResponse, .cancelled])
    func closedFailures(failure: LiveNowFailure) async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: .failed(failure))
        await until { monitor.failure == failure }
        #expect(monitor.snapshot == nil)
        #expect(monitor.nextRefreshAt == driver.clock.now.addingTimeInterval(60))
        #expect(!monitor.refresh())
        monitor.setDemand(channelIDs: driver.ids, active: false)
        monitor.setDemand(channelIDs: driver.ids, active: true)
        #expect(driver.requests.count == 1)
        driver.clock.advance(60)
        #expect(monitor.refresh())
        await driver.waitForRequests(2)
        driver.finish(1, with: driver.snapshot())
        await driver.waitForSleeps(1)
        #expect(monitor.failure == nil)
        monitor.reset()
    }

    @Test("Mismatched snapshot identities fail closed atomically")
    func invalidSnapshot() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: driver.snapshot(ids: driver.ids.reversed()))
        await until { monitor.failure == .unsupportedResponse }
        #expect(monitor.snapshot == nil)
        monitor.reset()
    }

    @Test("Age thresholds never present future or expired observations as current")
    func freshness() async {
        let driver = MonitorDriver()
        let monitor = driver.makeMonitor()
        monitor.setDemand(channelIDs: driver.ids, active: true)
        await driver.waitForRequests(1)
        driver.finish(0, with: driver.snapshot())
        await driver.waitForSleeps(1)
        for (age, expected) in [(-1.0, LiveNowFreshness.unavailable), (0, .current), (89, .current), (90, .stale), (299, .stale), (300, .unavailable)] {
            #expect(monitor.freshness(at: driver.clock.now.addingTimeInterval(age)) == expected)
        }
        monitor.reset()
    }

    private func until(_ predicate: @escaping @MainActor @Sendable () -> Bool) async {
        while !predicate() {
            await withCheckedContinuation { continuation in
                withObservationTracking { _ = predicate() } onChange: { continuation.resume() }
            }
        }
    }
}

private final class MonitorClock: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
}

@MainActor private final class MonitorDriver {
    let ids = [LiveChannelID("one"), LiveChannelID("two")]
    let clock = MonitorClock()
    private(set) var requests: [[LiveChannelID]] = []
    private(set) var delays: [TimeInterval] = []
    private var responses: [Int: CheckedContinuation<LiveNowAvailability, Never>] = [:]
    private var sleepers: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var sleepWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func makeMonitor() -> LiveNowMonitor {
        LiveNowMonitor(refresh: { await self.fetch($0) }, now: { [clock] in clock.now }, sleep: { try await self.sleep($0) })
    }

    func snapshot(ids: [LiveChannelID]? = nil, missing: Bool = false) -> LiveNowAvailability {
        .current(LiveNowSnapshot(observedAt: clock.now, channels: (ids ?? self.ids).map {
            LiveNowChannel(channelID: $0, state: missing ? .unavailable : .current(LiveNowProgram(title: "Synthetic program", kind: .item, startedAt: clock.now)))
        }))
    }

    private func fetch(_ ids: [LiveChannelID]) async -> LiveNowAvailability {
        await withCheckedContinuation { continuation in
            let index = requests.count
            responses[index] = continuation
            requests.append(ids)
            requestWaiters.removeAll { count, waiter in
                if requests.count >= count { waiter.resume(); return true }
                return false
            }
        }
    }

    private func sleep(_ seconds: TimeInterval) async throws {
        let index = delays.count
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[index] = continuation
                delays.append(seconds)
                sleepWaiters.removeAll { count, waiter in
                    if delays.count >= count { waiter.resume(); return true }
                    return false
                }
            }
        } onCancel: {
            Task { @MainActor in self.sleepers.removeValue(forKey: index)?.resume(throwing: CancellationError()) }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }
    func waitForSleeps(_ count: Int) async {
        guard delays.count < count else { return }
        await withCheckedContinuation { sleepWaiters.append((count, $0)) }
    }
    func finish(_ index: Int, with result: LiveNowAvailability) { responses.removeValue(forKey: index)!.resume(returning: result) }
    func wake(_ index: Int, advancing seconds: TimeInterval) {
        clock.advance(seconds)
        sleepers.removeValue(forKey: index)!.resume()
    }
}
