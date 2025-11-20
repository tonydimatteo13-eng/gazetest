import Foundation

public struct GameConfig {
    public let baselineTrialCount: Int
    public let sstTrialCount: Int
    public let goProbability: Double
    public let maxConsecutiveType: Int
    public let targetEccentricityDeg: Double
    public let fixationRadiusDeg: Double
    public let fixationSamplesRequired: Int
    public let goTimeoutMs: Int
    public let itiRangeMs: ClosedRange<Int>
    public let anticipationThresholdMs: Int
    public let stopSignalDelayRangeMs: ClosedRange<Int>
    public let samplingRateHz: Double
    public let rngSeed: UInt64
    public let isTestMode: Bool

    public init(
        baselineTrialCount: Int = 30,
        sstTrialCount: Int = 120,
        goProbability: Double = 0.6,
        maxConsecutiveType: Int = 3,
        targetEccentricityDeg: Double = 12.0,
        fixationRadiusDeg: Double = 3.0,
        fixationSamplesRequired: Int = 8,
        goTimeoutMs: Int = 650,
        itiRangeMs: ClosedRange<Int> = 1000...1500,
        anticipationThresholdMs: Int = 100,
        stopSignalDelayRangeMs: ClosedRange<Int> = 50...200,
        samplingRateHz: Double = 60.0,
        rngSeed: UInt64 = 0xF1F2F3F4,
        isTestMode: Bool = false
    ) {
        self.baselineTrialCount = baselineTrialCount
        self.sstTrialCount = sstTrialCount
        self.goProbability = goProbability
        self.maxConsecutiveType = maxConsecutiveType
        self.targetEccentricityDeg = targetEccentricityDeg
        self.fixationRadiusDeg = fixationRadiusDeg
        self.fixationSamplesRequired = fixationSamplesRequired
        self.goTimeoutMs = goTimeoutMs
        self.itiRangeMs = itiRangeMs
        self.anticipationThresholdMs = anticipationThresholdMs
        self.stopSignalDelayRangeMs = stopSignalDelayRangeMs
        self.samplingRateHz = samplingRateHz
        self.rngSeed = rngSeed
        self.isTestMode = isTestMode
    }

    public static let production = GameConfig()

    public static func test(seed: UInt64 = 0x5EEDC0DE) -> GameConfig {
        GameConfig(rngSeed: seed, isTestMode: true)
    }
}
