import Foundation

public struct AngleSample {
    public let timestamp: TimeInterval
    public let horizontalDeg: Double
    public let verticalDeg: Double
}

public struct SaccadeOutcome {
    public let reactionTimeMs: Int?
    public let enteredCorridor: Bool
    public let anticipation: Bool
}

public struct SaccadeDetector {
    public let corridorEntryDeg: Double = 6.0
    public let centralExclusionDeg: Double = 3.0
    public let anticipationThresholdMs: Int

    public init(anticipationThresholdMs: Int) {
        self.anticipationThresholdMs = anticipationThresholdMs
    }

    public func evaluate(samples: [AngleSample], goTime: TimeInterval, direction: TrialDirection) -> SaccadeOutcome {
        guard !samples.isEmpty else {
            return SaccadeOutcome(reactionTimeMs: nil, enteredCorridor: false, anticipation: false)
        }
        var reactionTime: Int?
        var anticipation = false
        let sign: Double = direction == .left ? -1.0 : 1.0

        for sample in samples {
            let dt = (sample.timestamp - goTime) * 1000.0
            if dt < 0 { continue }
            let horizontal = sample.horizontalDeg * sign
            if reactionTime == nil {
                if horizontal > centralExclusionDeg {
                    if dt < Double(anticipationThresholdMs) {
                        anticipation = true
                    }
                    if horizontal >= corridorEntryDeg {
                        reactionTime = Int(round(dt))
                        break
                    }
                }
            }
        }

        let entered = reactionTime != nil
        return SaccadeOutcome(reactionTimeMs: reactionTime, enteredCorridor: entered, anticipation: anticipation)
    }
}
