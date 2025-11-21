import Foundation

public struct TrialMetricsInput {
    public let goOnsetMs: Int
    public let rtMs: Int?
    public let goSuccess: Bool
    public let stopSuccess: Bool
    public let gazeRMSEDeg: Double
    public let viewingDistanceCm: Double
    public let headMotionFlag: Bool
    public let lostTrackingFlag: Bool

    public init(goOnsetMs: Int, rtMs: Int?, goSuccess: Bool, stopSuccess: Bool, gazeRMSEDeg: Double, viewingDistanceCm: Double, headMotionFlag: Bool, lostTrackingFlag: Bool) {
        self.goOnsetMs = goOnsetMs
        self.rtMs = rtMs
        self.goSuccess = goSuccess
        self.stopSuccess = stopSuccess
        self.gazeRMSEDeg = gazeRMSEDeg
        self.viewingDistanceCm = viewingDistanceCm
        self.headMotionFlag = headMotionFlag
        self.lostTrackingFlag = lostTrackingFlag
    }

}

public final class TrialEngine {
    private let config: GameConfig
    private let scheduler: TrialScheduler
    private var baselinePlan: [ScheduledTrial]
    private var sstPlan: [ScheduledTrial]
    private var baselineIndex: Int = 0
    private var sstIndex: Int = 0
    private var globalTrialCounter: Int = 0
    private var baselineValidGoCount: Int = 0
    private var sstValidGoCount: Int = 0
    private var sstValidStopCount: Int = 0
    private var sstCompletedCount: Int = 0
    private var shouldEndSSTEarly: Bool = false
    private(set) var completedTrials: [Trial] = []

    public init(config: GameConfig = .production) {
        self.config = config
        self.scheduler = TrialScheduler(config: config)
        self.baselinePlan = scheduler.baselineSchedule()
        self.sstPlan = scheduler.sstSchedule()
    }

    public func reset() {
        baselineIndex = 0
        sstIndex = 0
        globalTrialCounter = 0
        baselineValidGoCount = 0
        sstValidGoCount = 0
        sstValidStopCount = 0
        sstCompletedCount = 0
        shouldEndSSTEarly = false
        completedTrials.removeAll()
        baselinePlan = scheduler.baselineSchedule()
        sstPlan = scheduler.sstSchedule()
        print("[TrialEngine] reset – baselineCount=\(baselinePlan.count) sstCount=\(sstPlan.count)")
    }

    public func nextBaselineTrial() -> ScheduledTrial? {
        guard baselineIndex < baselinePlan.count else {
            print("[TrialEngine] nextBaselineTrial() – exhausted at index \(baselineIndex) / \(baselinePlan.count)")
            return nil
        }
        let trial = baselinePlan[baselineIndex]
        baselineIndex += 1
        print("[TrialEngine] nextBaselineTrial() -> index=\(trial.index) block=\(trial.block) type=\(trial.type) dir=\(trial.direction)")
        return trial
    }

    public func nextSSTTrial() -> ScheduledTrial? {
        if config.enableEarlyStop && shouldEndSSTEarly {
            print("[TrialEngine] nextSSTTrial() – early stop triggered after \(sstCompletedCount) SST trials (goValid=\(sstValidGoCount) stopValid=\(sstValidStopCount))")
            return nil
        }
        guard sstIndex < sstPlan.count else {
            print("[TrialEngine] nextSSTTrial() – exhausted at index \(sstIndex) / \(sstPlan.count)")
            return nil
        }
        let trial = sstPlan[sstIndex]
        sstIndex += 1
        print("[TrialEngine] nextSSTTrial() -> index=\(trial.index) block=\(trial.block) type=\(trial.type) dir=\(trial.direction) ssd=\(trial.ssdMs.map(String.init) ?? "nil")")
        return trial
    }

    @discardableResult public func record(trial scheduled: ScheduledTrial, metrics: TrialMetricsInput, gazeRMSE: Double? = nil) -> Trial {
        globalTrialCounter += 1
        let exclusions = computeExclusions(metrics: metrics)
        let trial = Trial(
            trialIndex: globalTrialCounter,
            block: scheduled.block,
            type: scheduled.type,
            direction: scheduled.direction,
            goOnsetMs: metrics.goOnsetMs,
            ssdMs: scheduled.ssdMs,
            rtMs: metrics.rtMs,
            goSuccess: metrics.goSuccess,
            stopSuccess: metrics.stopSuccess,
            gazeRMSEDeg: metrics.gazeRMSEDeg,
            viewingDistanceCm: metrics.viewingDistanceCm,
            headMotionFlag: metrics.headMotionFlag,
            lostTrackingFlag: metrics.lostTrackingFlag,
            exclusions: exclusions
        )
        completedTrials.append(trial)
        updateCountsAndEarlyStop(for: trial)
        return trial
    }

    private func computeExclusions(metrics: TrialMetricsInput) -> [TrialExclusion] {
        var out: [TrialExclusion] = []
        if let rt = metrics.rtMs, rt < config.anticipationThresholdMs {
            out.append(.anticipation)
        }
        if metrics.gazeRMSEDeg > 2.5 {
            out.append(.poorGaze)
        }
        if metrics.headMotionFlag {
            out.append(.headMotion)
        }
        if metrics.lostTrackingFlag {
            out.append(.lostTracking)
        }
        return out
    }

    private func updateCountsAndEarlyStop(for trial: Trial) {
        if trial.block == .sst {
            sstCompletedCount += 1
        }

        guard isIncludedForCounts(trial) else { return }

        switch trial.block {
        case .baseline:
            if trial.type == .go && trial.goSuccess {
                baselineValidGoCount += 1
            }
        case .sst:
            if trial.type == .go && trial.goSuccess {
                sstValidGoCount += 1
            } else if trial.type == .stop {
                sstValidStopCount += 1
            }
        }

        if config.enableEarlyStop,
           sstCompletedCount >= 40,
           sstValidGoCount >= 20,
           sstValidStopCount >= 16 {
            shouldEndSSTEarly = true
            print("[TrialEngine] Early stop criteria met – sstCompleted=\(sstCompletedCount) goValid=\(sstValidGoCount) stopValid=\(sstValidStopCount)")
        }
    }

    private func isIncludedForCounts(_ trial: Trial) -> Bool {
        guard !trial.headMotionFlag, !trial.lostTrackingFlag else { return false }
        if trial.gazeRMSEDeg > 2.5 { return false }
        if let rt = trial.rtMs, rt < config.anticipationThresholdMs { return false }
        return true
    }
}
