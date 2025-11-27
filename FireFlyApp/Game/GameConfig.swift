import Foundation

public struct GameConfig {
    public let baselineTrialCount: Int
    public let sstTrialCount: Int
    public let goProbability: Double
    public let maxConsecutiveType: Int
    public let maxSameSideInRow: Int
    public let targetEccentricityDeg: Double
    public let fixationRadiusDeg: Double
    public let fixationSamplesRequired: Int
    public let goTimeoutMs: Int
    public var goDeadlineMs: Int { goTimeoutMs }
    public let itiRangeMs: ClosedRange<Int>
    public let anticipationThresholdMs: Int
    public let stopSignalDelayRangeMs: ClosedRange<Int>
    public let fixationDurationMsRange: ClosedRange<Int>
    public let samplingRateHz: Double
    public let rngSeed: UInt64
    public let enableEarlyStop: Bool
    public let isTestMode: Bool
    public let trainingGoCount: Int
    public let trainingStopCount: Int
    public let centralExclusionDeg: Double
    public let corridorThresholdDeg: Double
    public let maxTrialGazeRMSEDeg: Double
    public let maxHeadMotionStepCm: Double
    public let maxHeadMotionRangeCm: Double
    public let maxLostTrackingGapMs: Int

    // Corridor/quality thresholds (spec alignment noted in comments):
    // - corridorThresholdDeg: spec target 6°; default 5° to keep toddler/field data feasible while preserving corridor logic.
    // - centralExclusionDeg: spec ~2° to ignore central noise before counting a saccade.
    // - anticipationThresholdMs: spec 100 ms; default 120 ms to reduce over-penalizing very fast looks.
    // - maxTrialGazeRMSEDeg: per-trial quality gate; default 3.0° to align with Good/OK calibration bands but tolerate mild noise.

    public init(
        baselineTrialCount: Int = 10,
        sstTrialCount: Int = 60,
        goProbability: Double = 0.6,
        maxConsecutiveType: Int = 3,
        maxSameSideInRow: Int = 3,
        targetEccentricityDeg: Double = 12.0,
        fixationRadiusDeg: Double = 3.0,
        fixationSamplesRequired: Int = 18,
        goTimeoutMs: Int = 650,
        itiRangeMs: ClosedRange<Int> = 500...700,
        anticipationThresholdMs: Int = 120,
        stopSignalDelayRangeMs: ClosedRange<Int> = 50...200,
        fixationDurationMsRange: ClosedRange<Int> = 1500...2000,
        samplingRateHz: Double = 60.0,
        rngSeed: UInt64 = 0xF1F2F3F4,
        enableEarlyStop: Bool = true,
        isTestMode: Bool = false,
        trainingGoCount: Int = 6,
        trainingStopCount: Int = 4,
        centralExclusionDeg: Double = 2.0,
        corridorThresholdDeg: Double = 5.0,
        maxTrialGazeRMSEDeg: Double = 3.0,
        maxHeadMotionStepCm: Double = 3.0,
        maxHeadMotionRangeCm: Double = 5.0,
        maxLostTrackingGapMs: Int = 1500
    ) {
        self.baselineTrialCount = baselineTrialCount
        self.sstTrialCount = sstTrialCount
        self.goProbability = goProbability
        self.maxConsecutiveType = maxConsecutiveType
        self.maxSameSideInRow = maxSameSideInRow
        self.targetEccentricityDeg = targetEccentricityDeg
        self.fixationRadiusDeg = fixationRadiusDeg
        self.fixationSamplesRequired = fixationSamplesRequired
        self.goTimeoutMs = goTimeoutMs
        self.itiRangeMs = itiRangeMs
        self.anticipationThresholdMs = anticipationThresholdMs
        self.stopSignalDelayRangeMs = stopSignalDelayRangeMs
        self.fixationDurationMsRange = fixationDurationMsRange
        self.samplingRateHz = samplingRateHz
        self.rngSeed = rngSeed
        self.enableEarlyStop = enableEarlyStop
        self.isTestMode = isTestMode
        self.trainingGoCount = trainingGoCount
        self.trainingStopCount = trainingStopCount
        self.centralExclusionDeg = centralExclusionDeg
        self.corridorThresholdDeg = corridorThresholdDeg
        self.maxTrialGazeRMSEDeg = maxTrialGazeRMSEDeg
        self.maxHeadMotionStepCm = maxHeadMotionStepCm
        self.maxHeadMotionRangeCm = maxHeadMotionRangeCm
        self.maxLostTrackingGapMs = maxLostTrackingGapMs
    }

    /// Default short-form clinical production config (~4–6 minutes).
    /// Mirrors Kelly et al. 2021 oculomotor SST (12° step targets; central STOP signal)
    /// while targeting per-session minimums of:
    /// - Baseline: ≥ 8 valid GO trials
    /// - SST: ≥ 20 valid GO and ≥ 16 valid STOP trials.
    public static let production = GameConfig()

    /// Explicit alias for the short-form production configuration.
    public static let productionShortForm = GameConfig()

    public static func test(seed: UInt64 = 0x5EEDC0DE) -> GameConfig {
        GameConfig(
            baselineTrialCount: 30,
            sstTrialCount: 120,
            rngSeed: seed,
            enableEarlyStop: false,
            isTestMode: true
        )
    }
}
