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

    /// Baseline block:
    /// - GO-only trials at ±targetEccentricityDeg (step targets).
    /// - Short-form protocol (Kelly et al. 2021–aligned) targets 10 trials,
    ///   yielding ≥ 8 valid GO trials under typical conditions.
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

    /// Stop-signal block (SST) schedule:
    /// - Uses config.sstTrialCount as an upper bound (short-form target: 60 trials).
    /// - Preserves GO:STOP ratio via config.goProbability (default 0.6; STOP = 1 − GO).
    /// - Enforces at most config.maxConsecutiveType GO or STOP trials in a row.
    /// - Enforces at most config.maxSameSideInRow left or right trials in a row.
    /// - On STOP trials, draws SSD uniformly from config.stopSignalDelayRangeMs
    ///   (default 50–200 ms) to match the oculomotor SST timing in Kelly et al. 2021.
    public func sstSchedule() -> [ScheduledTrial] {
        let total = config.sstTrialCount
        let targetGo = Int(round(Double(total) * config.goProbability))
        let targetStop = total - targetGo
        var remainingGo = targetGo
        var remainingStop = targetStop

        var trials: [ScheduledTrial] = []
        var lastType: TrialType = .go
        var streak = 0
        var lastDirection: TrialDirection?
        var sideStreak = 0

        for index in 0..<total {
            let type = pickType(remainingGo: &remainingGo, remainingStop: &remainingStop, lastType: lastType, streak: &streak)
            lastType = type
            let direction = pickDirection(lastDirection: &lastDirection, streak: &sideStreak)
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

    private func pickDirection(lastDirection: inout TrialDirection?, streak: inout Int) -> TrialDirection {
        let forceOtherSide = streak >= config.maxSameSideInRow
        let randomRoll = rng.next() & 1
        let randomDirection: TrialDirection = randomRoll == 0 ? .left : .right

        let chosen: TrialDirection
        if forceOtherSide, let last = lastDirection {
            chosen = last == .left ? .right : .left
        } else {
            chosen = randomDirection
        }

        if let last = lastDirection, chosen == last {
            streak += 1
        } else {
            streak = 1
        }
        lastDirection = chosen
        return chosen
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
