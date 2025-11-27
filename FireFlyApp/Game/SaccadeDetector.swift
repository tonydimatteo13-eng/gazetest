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
    public let firstEntry: CorridorEntryEvent?
    public let horizontalMinDeg: Double
    public let horizontalMaxDeg: Double
}

public struct CorridorEntryEvent {
    public let timestampMs: Int
    public let horizontalDeg: Double
    public let direction: TrialDirection
}

public struct SaccadeDetector {
    /// Geometry and timing thresholds are sourced from GameConfig so they stay aligned with
    /// the FireflyStopSignalAgent spec (12° step targets, central STOP signal).
    /// - corridorEntryDeg: angular threshold to count a saccade toward the target (spec target: 6°; pilot default: 5°).
    /// - centralExclusionDeg: samples inside this radius are ignored so micro-noise does not trigger a saccade (spec: ~2°).
    /// - anticipationThresholdMs: saccades that leave the central exclusion before this time are flagged as anticipatory.
    public let corridorEntryDeg: Double
    public let centralExclusionDeg: Double
    public let anticipationThresholdMs: Int

    public init(anticipationThresholdMs: Int, corridorEntryDeg: Double, centralExclusionDeg: Double) {
        self.anticipationThresholdMs = anticipationThresholdMs
        self.corridorEntryDeg = corridorEntryDeg
        self.centralExclusionDeg = centralExclusionDeg
    }

    public func evaluate(samples: [AngleSample], goTime: TimeInterval, direction: TrialDirection) -> SaccadeOutcome {
        guard !samples.isEmpty else {
            return SaccadeOutcome(
                reactionTimeMs: nil,
                enteredCorridor: false,
                anticipation: false,
                firstEntry: nil,
                horizontalMinDeg: 0,
                horizontalMaxDeg: 0
            )
        }
        var reactionTime: Int?
        var anticipation = false
        var firstEntry: CorridorEntryEvent?
        var horizontalMin = samples.first?.horizontalDeg ?? 0
        var horizontalMax = horizontalMin
        let sign: Double = direction == .left ? -1.0 : 1.0

        for sample in samples {
            horizontalMin = min(horizontalMin, sample.horizontalDeg)
            horizontalMax = max(horizontalMax, sample.horizontalDeg)
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
                        firstEntry = CorridorEntryEvent(
                            timestampMs: Int(round(dt)),
                            horizontalDeg: sample.horizontalDeg,
                            direction: direction
                        )
                        break
                    }
                }
            }
        }

        let entered = reactionTime != nil
        return SaccadeOutcome(
            reactionTimeMs: reactionTime,
            enteredCorridor: entered,
            anticipation: anticipation,
            firstEntry: firstEntry,
            horizontalMinDeg: horizontalMin,
            horizontalMaxDeg: horizontalMax
        )
    }
}
