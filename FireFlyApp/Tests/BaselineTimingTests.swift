import XCTest
@testable import FireFlyCore

final class BaselineTimingTests: XCTestCase {
    func testBaselineMeanReactsTo250msSaccades() {
        let config = GameConfig.test(seed: 0xCAFEBABE)
        let engine = TrialEngine(config: config)
        var trials: [Trial] = []
        for _ in 0..<config.baselineTrialCount {
            guard let scheduled = engine.nextBaselineTrial() else { continue }
            let metrics = TrialMetricsInput(
                goOnsetMs: 0,
                rtMs: 250,
                goSuccess: true,
                stopSuccess: false,
                gazeRMSEDeg: 0.5,
                viewingDistanceCm: 60,
                headMotionFlag: false,
                lostTrackingFlag: false
            )
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
        XCTAssertGreaterThanOrEqual(results.baselineRTMs, 240)
        XCTAssertLessThanOrEqual(results.baselineRTMs, 260)
    }

    func testTimeoutMarkedAsMiss() {
        let config = GameConfig.test(seed: 0x12345678)
        let engine = TrialEngine(config: config)
        guard let scheduled = engine.nextBaselineTrial() else {
            XCTFail("No baseline trial")
            return
        }
        let metrics = TrialMetricsInput(
            goOnsetMs: 0,
            rtMs: nil,
            goSuccess: false,
            stopSuccess: false,
            gazeRMSEDeg: 0.5,
            viewingDistanceCm: 60,
            headMotionFlag: false,
            lostTrackingFlag: false
        )
        let trial = engine.record(trial: scheduled, metrics: metrics)
        XCTAssertFalse(trial.goSuccess)
        XCTAssertNil(trial.rtMs)
    }
}
