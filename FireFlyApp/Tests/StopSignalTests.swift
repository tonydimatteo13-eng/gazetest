import XCTest
@testable import FireFlyCore

final class StopSignalTests: XCTestCase {
    func testPerfectStoppingYieldsHighAccuracy() {
        let config = GameConfig.test(seed: 0x42424242)
        let engine = TrialEngine(config: config)
        var trials: [Trial] = []
        while let scheduled = engine.nextSSTTrial() {
            let metrics: TrialMetricsInput
            switch scheduled.type {
            case .go:
                metrics = TrialMetricsInput(
                    goOnsetMs: 0,
                    rtMs: 320,
                    goSuccess: true,
                    stopSuccess: false,
                    gazeRMSEDeg: 0.6,
                    viewingDistanceCm: 60,
                    headMotionFlag: false,
                    lostTrackingFlag: false
                )
            case .stop:
                metrics = TrialMetricsInput(
                    goOnsetMs: 0,
                    rtMs: nil,
                    goSuccess: false,
                    stopSuccess: true,
                    gazeRMSEDeg: 0.6,
                    viewingDistanceCm: 60,
                    headMotionFlag: false,
                    lostTrackingFlag: false
                )
            }
            trials.append(engine.record(trial: scheduled, metrics: metrics))
        }
        let meta = SessionMeta(
            sessionUID: UUID(),
            appVersion: "1.0",
            deviceModel: "Test",
            osVersion: "17.0",
            viewingDistanceMeanCm: 60,
            calibrationRMSEDeg: 1.0,
            ageBucket: .preferNotToSay,
            buildID: "1"
        )
        let results = Scorer.computeResults(session: meta, trials: trials)
        XCTAssertGreaterThanOrEqual(results.stoppingAccuracyPct, 95)
    }

    func testSSDRangeCoversUniformWindow() {
        let config = GameConfig.test(seed: 0x99ABCDEF)
        let scheduler = TrialScheduler(config: config)
        let schedule = scheduler.sstSchedule()
        let ssds = schedule.compactMap { $0.ssdMs }
        XCTAssertFalse(ssds.isEmpty)
        guard let minSSD = ssds.min(), let maxSSD = ssds.max() else {
            XCTFail("Missing SSD values")
            return
        }
        XCTAssertGreaterThanOrEqual(minSSD, 50 - 10)
        XCTAssertLessThanOrEqual(maxSSD, 200 + 10)
        XCTAssertGreaterThan(maxSSD - minSSD, 120)
    }
}
