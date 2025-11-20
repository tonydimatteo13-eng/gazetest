import XCTest
@testable import FireFlyCore

final class ExclusionTests: XCTestCase {
    func testTrialsBelowRTThresholdExcluded() {
        let config = GameConfig.test(seed: 0x10101010)
        let engine = TrialEngine(config: config)
        var trials: [Trial] = []
        // Valid GO
        if let trial = engine.nextBaselineTrial() {
            trials.append(engine.record(trial: trial, metrics: TrialMetricsInput(
                goOnsetMs: 0,
                rtMs: 250,
                goSuccess: true,
                stopSuccess: false,
                gazeRMSEDeg: 0.5,
                viewingDistanceCm: 60,
                headMotionFlag: false,
                lostTrackingFlag: false
            )))
        }
        // Invalid due to anticipation
        if let trial = engine.nextBaselineTrial() {
            trials.append(engine.record(trial: trial, metrics: TrialMetricsInput(
                goOnsetMs: 0,
                rtMs: 80,
                goSuccess: true,
                stopSuccess: false,
                gazeRMSEDeg: 0.5,
                viewingDistanceCm: 60,
                headMotionFlag: false,
                lostTrackingFlag: false
            )))
        }
        // Invalid due to gaze RMSE
        if let trial = engine.nextBaselineTrial() {
            trials.append(engine.record(trial: trial, metrics: TrialMetricsInput(
                goOnsetMs: 0,
                rtMs: 240,
                goSuccess: true,
                stopSuccess: false,
                gazeRMSEDeg: 3.0,
                viewingDistanceCm: 60,
                headMotionFlag: false,
                lostTrackingFlag: false
            )))
        }

        XCTAssertEqual(trials.count, 3)
        XCTAssertEqual(trials.first?.block, .baseline)
        XCTAssertEqual(trials.first?.rtMs, 250)
        XCTAssertFalse(trials.first?.headMotionFlag ?? true)
        XCTAssertTrue(trials.first?.goSuccess ?? false)
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
        XCTAssertEqual(results.includedGo, 1)
    }
}
