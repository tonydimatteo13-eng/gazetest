import Foundation

public struct ScheduledTrial {
    public let index: Int
    public let block: TrialBlock
    public let type: TrialType
    public let direction: TrialDirection
    public let ssdMs: Int?

    public init(index: Int, block: TrialBlock, type: TrialType, direction: TrialDirection, ssdMs: Int?) {
        self.index = index
        self.block = block
        self.type = type
        self.direction = direction
        self.ssdMs = ssdMs
    }

}

public final class TrialScheduler {
    private let config: GameConfig
    private var rng: SeededGenerator

    public init(config: GameConfig) {
        self.config = config
        self.rng = SeededGenerator(seed: config.rngSeed)
    }

    public func baselineSchedule() -> [ScheduledTrial] {
        var trials: [ScheduledTrial] = []
        var directionToggle: Bool = false
        for index in 0..<config.baselineTrialCount {
            let direction: TrialDirection = directionToggle ? .right : .left
            directionToggle.toggle()
            trials.append(ScheduledTrial(
                index: index,
                block: .baseline,
                type: .go,
                direction: direction,
                ssdMs: nil
            ))
        }
        return trials
    }

    public func sstSchedule() -> [ScheduledTrial] {
        let total = config.sstTrialCount
        let targetGo = Int(round(Double(total) * config.goProbability))
        let targetStop = total - targetGo
        var remainingGo = targetGo
        var remainingStop = targetStop

        var trials: [ScheduledTrial] = []
        var lastType: TrialType = .go
        var streak = 0

        for index in 0..<total {
            let type = pickType(remainingGo: &remainingGo, remainingStop: &remainingStop, lastType: lastType, streak: &streak)
            lastType = type
            let direction = pickDirection()
            let ssd = type == .stop ? randomSSD() : nil
            trials.append(ScheduledTrial(
                index: index,
                block: .sst,
                type: type,
                direction: direction,
                ssdMs: ssd
            ))
        }
        return trials
    }

    private func pickType(remainingGo: inout Int, remainingStop: inout Int, lastType: TrialType, streak: inout Int) -> TrialType {
        let forceOther = streak >= config.maxConsecutiveType
        let canGo = remainingGo > 0
        let canStop = remainingStop > 0

        let chosen: TrialType
        if forceOther {
            if lastType == .go, canStop {
                chosen = .stop
            } else if lastType == .stop, canGo {
                chosen = .go
            } else {
                chosen = canGo ? .go : .stop
            }
        } else {
            if !canGo { chosen = .stop }
            else if !canStop { chosen = .go }
            else {
                let total = remainingGo + remainingStop
                let threshold = Double(remainingGo) / Double(total)
                let roll = Double(rng.next()) / Double(UInt64.max)
                chosen = roll <= threshold ? .go : .stop
            }
        }

        if chosen == .go {
            remainingGo -= 1
        } else {
            remainingStop -= 1
        }

        if chosen == lastType {
            streak += 1
        } else {
            streak = 1
        }
        return chosen
    }

    private func pickDirection() -> TrialDirection {
        let roll = rng.next() & 1
        return roll == 0 ? .left : .right
    }

    private func randomSSD() -> Int {
        let range = config.stopSignalDelayRangeMs
        let min = range.lowerBound
        let max = range.upperBound
        let roll = Double(rng.next()) / Double(UInt64.max)
        let value = Double(min) + roll * Double(max - min)
        return Int(round(value))
    }
}
