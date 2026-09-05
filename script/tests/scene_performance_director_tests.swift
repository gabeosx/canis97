import Foundation

@main struct ScenePerformanceDirectorChecks {
    typealias Plan = ScenePerformancePlan
    typealias Director = ScenePerformanceDirector
    static func main() throws {
        let actors = ["manta", "school", "jelly", "shrimp", "cuttlefish", "eel", "shark"]
        var repertoire: [Plan.Performance] = []
        for (index, actor) in actors.enumerated() {
            let tier: Plan.Tier = index == 6 ? .rare : (index >= 4 ? .uncommon : .common)
            for variant in 0..<3 {
                repertoire.append(.init(identifier: "\(actor)_\(variant)", actor: actor, tier: tier,
                                        duration: tier == .rare ? 28 : 16, cooldown: tier == .rare ? 1_800 : 300,
                                        actorCooldown: tier == .rare ? 600 : 75))
            }
        }
        let cadences: [Plan.Cadence] = [
            .init(tier: .common, initialDelay: .init(6,6), interval: .init(20,55)),
            .init(tier: .uncommon, initialDelay: .init(150,150), interval: .init(180,360)),
            .init(tier: .rare, initialDelay: .init(540,960), interval: .init(720,1_500))]
        func plan(_ seed: UInt64) throws -> Plan {
            try .init(seed: seed, cadences: cadences, performances: repertoire, rest: .init(6,14))
        }
        func simulate(_ seed: UInt64) throws -> [Director.Selection] {
            var director = Director(plan: try plan(seed))
            var time = 0.0
            var visits: [Director.Selection] = []
            var previousEnds: [String:Double] = [:]
            var actorEnds: [String:Double] = [:]
            while time < 8*3_600 {
                if let selection = director.next(activeTime: time) {
                    if let previous = visits.last {
                        precondition(selection.startedAt >= previous.endsAt+6)
                        precondition(selection.actor != previous.actor)
                        precondition(selection.startedAt-previous.endsAt <= 90)
                    }
                    if let previous = previousEnds[selection.identifier] {
                        let cooldown = repertoire.first { $0.identifier == selection.identifier }!.cooldown
                        precondition(selection.startedAt-previous >= cooldown)
                    }
                    if let previous = actorEnds[selection.actor] {
                        let cooldown = repertoire.first { $0.identifier == selection.identifier }!.actorCooldown
                        precondition(selection.startedAt-previous >= cooldown)
                    }
                    previousEnds[selection.identifier] = selection.endsAt
                    actorEnds[selection.actor] = selection.endsAt
                    visits.append(selection)
                }
                guard let delay = director.nextWakeDelay(activeTime: time) else { fatalError("Unexpected starvation") }
                precondition(delay >= 0.01 && delay.isFinite)
                time += delay
            }
            precondition(Set(visits.map(\.identifier)).count == repertoire.count)
            return visits
        }
        for seed in UInt64(1)...32 { _ = try simulate(seed) }
        let expected = try simulate(97)
        let repeated = try simulate(97), different = try simulate(123)
        precondition(expected == repeated)
        precondition(expected != different)

        // Copying/holding the director across host suspension preserves state.
        var original = Director(plan: try plan(97))
        _ = original.next(activeTime: 6)
        var resumed = original
        for time in stride(from: 7.0, to: 1_200, by: 1) {
            precondition(original.next(activeTime: time) == resumed.next(activeTime: time))
        }

        // No visit is allowed when its host-owned condition is false. No timer
        // is requested until a context update can make work eligible.
        let conditional = try Plan(seed: 1, cadences: [.init(tier:.common,initialDelay:.init(0,0),interval:.init(4,4))],
            performances:[.init(identifier:"inspect_jar",actor:"cuttlefish",tier:.common,duration:10,
                                cooldown:20,actorCooldown:20,requiresSongFavorite:true)],rest:.init(1,1))
        var conditionDirector = Director(plan: conditional)
        precondition(conditionDirector.next(activeTime:0) == nil)
        precondition(conditionDirector.nextWakeDelay(activeTime:0) == nil)
        precondition(conditionDirector.next(activeTime:0,context:.init(songFavorite:true))?.identifier == "inspect_jar")
        precondition(conditionDirector.next(activeTime:100,context:.init(songFavorite:true)) != nil)
        precondition(conditionDirector.next(activeTime:100,context:.init(songFavorite:true)) == nil)
        // Unknown/nonmonotonic clocks cannot mutate the director.
        let validDelay = conditionDirector.nextWakeDelay(activeTime:100,context:.init(songFavorite:true))
        precondition(conditionDirector.next(activeTime:.nan) == nil)
        precondition(conditionDirector.next(activeTime:99) == nil)
        precondition(conditionDirector.nextWakeDelay(activeTime:100,context:.init(songFavorite:true)) == validDelay)

        // A future rare visitor must not prevent normal common activity.
        let sparsePlan = try Plan(seed: 1, cadences: [
            .init(tier: .common, initialDelay: .init(0,0), interval: .init(4,4)),
            .init(tier: .rare, initialDelay: .init(1800,1800), interval: .init(1800,1800))
        ], performances: [
            .init(identifier: "common", actor: "fish", tier: .common, duration: 2, cooldown: 0, actorCooldown: 0),
            .init(identifier: "rare", actor: "shark", tier: .rare, duration: 2, cooldown: 0, actorCooldown: 0)
        ], rest: .init(1,1))
        var sparse = Director(plan: sparsePlan)
        precondition(sparse.next(activeTime: 0)?.identifier == "common")
        precondition(sparse.nextWakeDelay(activeTime: 2) == 4)
        precondition(sparse.next(activeTime: 6)?.identifier == "common")
        precondition(sparse.next(activeTime: 1800)?.identifier == "rare")

        func reject(_ body: () throws -> Plan) {
            do { _ = try body(); fatalError("Invalid plan accepted") }
            catch Plan.Failure.invalidPlan {} catch { fatalError("Unexpected error") }
        }
        reject { try Plan(seed:1,cadences:cadences,performances:[],rest:.init(6,14)) }
        reject { try Plan(seed:1,cadences:cadences+cadences,performances:repertoire,rest:.init(6,14)) }
        reject { try Plan(seed:1,cadences:cadences,performances:repertoire+repertoire,rest:.init(6,14)) }
        reject { try Plan(seed:1,cadences:cadences,performances:repertoire,rest:.init(.nan,14)) }
        reject { try Plan(seed:1,cadences:[.init(tier:.common,initialDelay:.init(0,0),interval:.init(0,1))],performances:repertoire,rest:.init(6,14)) }
        for duration in [0.0,31,.infinity] {
            reject { try Plan(seed:1,cadences:[cadences[0]],performances:[.init(identifier:"bad",actor:"manta",tier:.common,duration:duration,cooldown:0,actorCooldown:0)],rest:.init(6,14)) }
        }
        reject { try Plan(seed:1,cadences:[cadences[0]],performances:[.init(identifier:"../bad",actor:"manta",tier:.common,duration:1,cooldown:0,actorCooldown:0)],rest:.init(6,14)) }
        print("PASS: 34 seeded eight-hour schedules, reproducibility, cooldowns, no pileups/starvation, context gating, suspension state, clock and plan rejection checks")
    }
}
