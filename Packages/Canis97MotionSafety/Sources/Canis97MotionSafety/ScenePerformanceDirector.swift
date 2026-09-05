import Foundation

/// Bounded authoring inputs for the app-owned long-session director. These are
/// scheduling values, not executable skin instructions or a wall-clock timer.
public struct ScenePerformancePlan: Equatable, Sendable {
    public enum Tier: String, Codable, CaseIterable, Sendable {
        case common, uncommon, rare
    }

    public struct Interval: Equatable, Sendable {
        public let minimum: Double
        public let maximum: Double
        public init(_ minimum: Double, _ maximum: Double) {
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    public struct Cadence: Equatable, Sendable {
        public let tier: Tier
        public let initialDelay: Interval
        public let interval: Interval
        public init(tier: Tier, initialDelay: Interval, interval: Interval) {
            self.tier = tier
            self.initialDelay = initialDelay
            self.interval = interval
        }
    }

    public struct Performance: Equatable, Sendable {
        public let identifier: String
        public let actor: String
        public let tier: Tier
        public let duration: Double
        public let cooldown: Double
        public let actorCooldown: Double
        public let requiresSongFavorite: Bool?
        public let requiresChannelFavorite: Bool?

        public init(identifier: String, actor: String, tier: Tier, duration: Double,
                    cooldown: Double, actorCooldown: Double,
                    requiresSongFavorite: Bool? = nil, requiresChannelFavorite: Bool? = nil) {
            self.identifier = identifier
            self.actor = actor
            self.tier = tier
            self.duration = duration
            self.cooldown = cooldown
            self.actorCooldown = actorCooldown
            self.requiresSongFavorite = requiresSongFavorite
            self.requiresChannelFavorite = requiresChannelFavorite
        }
    }

    public enum Failure: Error { case invalidPlan }
    public let seed: UInt64
    public let cadences: [Cadence]
    public let performances: [Performance]
    public let rest: Interval

    public init(seed: UInt64, cadences: [Cadence], performances: [Performance], rest: Interval) throws {
        func identifier(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45
            }
        }
        func interval(_ value: Interval, floor: Double, ceiling: Double) -> Bool {
            value.minimum.isFinite && value.maximum.isFinite && value.minimum >= floor &&
                value.maximum >= value.minimum && value.maximum <= ceiling
        }
        guard (1...3).contains(cadences.count), (1...32).contains(performances.count),
              Set(cadences.map(\.tier)).count == cadences.count,
              Set(performances.map(\.identifier)).count == performances.count,
              interval(rest, floor: 1, ceiling: 60),
              cadences.allSatisfy({ interval($0.initialDelay, floor: 0, ceiling: 1_800) &&
                  interval($0.interval, floor: 4, ceiling: 1_800) }),
              performances.allSatisfy({ p in
                  identifier(p.identifier) && identifier(p.actor) &&
                      p.duration.isFinite && (0.1...30).contains(p.duration) &&
                      p.cooldown.isFinite && (0...3_600).contains(p.cooldown) &&
                      p.actorCooldown.isFinite && (0...3_600).contains(p.actorCooldown) &&
                      cadences.contains(where: { $0.tier == p.tier })
              }),
              cadences.allSatisfy({ c in performances.contains(where: { $0.tier == c.tier }) })
        else { throw Failure.invalidPlan }
        self.seed = seed
        self.cadences = cadences
        self.performances = performances
        self.rest = rest
    }
}

/// Pure deterministic scheduling state. The host advances `activeTime` only
/// while selected/visible/playing/within budget and without Reduce Motion.
/// Keeping this value across suspension preserves bags, deadlines and cooldowns.
/// No Foundation Timer, Dispatch queue, network, NSApplication or persistence.
public struct ScenePerformanceDirector: Sendable {
    public struct Context: Equatable, Sendable {
        public var songFavorite: Bool
        public var channelFavorite: Bool
        public init(songFavorite: Bool = false, channelFavorite: Bool = false) {
            self.songFavorite = songFavorite
            self.channelFavorite = channelFavorite
        }
    }

    public struct Selection: Equatable, Sendable {
        public let identifier: String
        public let actor: String
        public let tier: ScenePerformancePlan.Tier
        public let startedAt: Double
        public let endsAt: Double
    }

    private let plan: ScenePerformancePlan
    private var rng: UInt64
    private var due: [ScenePerformancePlan.Tier: Double] = [:]
    private var bags: [ScenePerformancePlan.Tier: [Int]] = [:]
    private var variantReady: [String: Double] = [:]
    private var actorReady: [String: Double] = [:]
    private var lastActor: String?
    private var busyUntil: Double = 0
    private var lastTime: Double = 0

    public init(plan: ScenePerformancePlan) {
        self.plan = plan
        self.rng = plan.seed == 0 ? 0x9E3779B97F4A7C15 : plan.seed
        for cadence in plan.cadences {
            due[cadence.tier] = draw(cadence.initialDelay)
        }
    }

    /// Select at most one performance. A late host wakeup starts one fresh
    /// performance; it never emits a backlog of missed visitors.
    public mutating func next(activeTime: Double, context: Context = .init()) -> Selection? {
        guard activeTime.isFinite, activeTime >= lastTime else { return nil }
        lastTime = activeTime
        guard activeTime >= busyUntil else { return nil }
        for tier in [ScenePerformancePlan.Tier.rare, .uncommon, .common] {
            guard let deadline = due[tier], activeTime >= deadline else { continue }
            if bags[tier, default: []].isEmpty {
                var order = plan.performances.indices.filter { plan.performances[$0].tier == tier }
                if order.count > 1 {
                    for i in stride(from: order.count-1, through: 1, by: -1) {
                        order.swapAt(i, Int(random() % UInt64(i+1)))
                    }
                }
                bags[tier] = order
            }
            let candidates = plan.performances.indices.filter {
                plan.performances[$0].tier == tier && eligible($0, at: activeTime, context: context)
            }
            guard !candidates.isEmpty else { continue }
            let selected: Int
            if let bagIndex = bags[tier]!.firstIndex(where: { candidates.contains($0) }) {
                selected = bags[tier]!.remove(at: bagIndex)
            } else {
                // An ineligible residual bag cannot starve the entire tier.
                selected = candidates[Int(random() % UInt64(candidates.count))]
            }
            let performance = plan.performances[selected]
            let end = activeTime + performance.duration
            lastActor = performance.actor
            actorReady[performance.actor] = end + performance.actorCooldown
            variantReady[performance.identifier] = end + performance.cooldown
            busyUntil = end + draw(plan.rest)
            let cadence = plan.cadences.first { $0.tier == tier }!
            due[tier] = end + draw(cadence.interval)
            return Selection(identifier: performance.identifier, actor: performance.actor,
                             tier: tier, startedAt: activeTime, endsAt: end)
        }
        return nil
    }

    /// Earliest useful single wakeup. nil means the host must wait for a context
    /// change. This avoids a polling timer when all visitor conditions are false.
    public func nextWakeDelay(activeTime: Double, context: Context = .init()) -> Double? {
        guard activeTime.isFinite, activeTime >= lastTime else { return nil }
        let deadlines = plan.performances.indices.compactMap { index -> Double? in
            let p = plan.performances[index]
            guard matches(p, context), let tierDue = due[p.tier] else { return nil }
            let deadline = max(activeTime, tierDue, busyUntil, variantReady[p.identifier, default: 0], actorReady[p.actor, default: 0])
            guard actorCanFollow(p.actor, at: deadline, context: context) else { return nil }
            return deadline
        }
        guard let deadline = deadlines.min() else { return nil }
        return max(0.01, deadline-activeTime)
    }

    private func eligible(_ index: Int, at time: Double, context: Context) -> Bool {
        let p = plan.performances[index]
        return matches(p, context) && actorCanFollow(p.actor, at: time, context: context) &&
            time >= variantReady[p.identifier, default: 0] && time >= actorReady[p.actor, default: 0]
    }

    private func matches(_ p: ScenePerformancePlan.Performance, _ c: Context) -> Bool {
        (p.requiresSongFavorite == nil || p.requiresSongFavorite == c.songFavorite) &&
            (p.requiresChannelFavorite == nil || p.requiresChannelFavorite == c.channelFavorite)
    }

    private func actorCanFollow(_ actor: String, at time: Double, context: Context) -> Bool {
        // Prefer another actor only when it is actually ready now. An actor in
        // a rare tier or on a long cooldown must not starve the common cadence.
        actor != lastActor || !plan.performances.contains { p in
            p.actor != actor && matches(p, context) &&
                time >= due[p.tier, default: .infinity] &&
                time >= variantReady[p.identifier, default: 0] &&
                time >= actorReady[p.actor, default: 0]
        }
    }

    private mutating func random() -> UInt64 {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return rng
    }

    private mutating func draw(_ range: ScenePerformancePlan.Interval) -> Double {
        let fraction = Double(random() >> 11) / 9_007_199_254_740_992
        return range.minimum + (range.maximum-range.minimum)*fraction
    }
}
