import XCTest
@testable import FireFlyCore

final class UploadQueueTests: XCTestCase {
    func testTrialChunkingProducesThreeBatches() async throws {
        let mock = MockUploadService()
        mock.sessionHandler = { _ in "recSession" }
        var batchSizes: [Int] = []
        mock.trialsHandler = { _ , trials in
            batchSizes.append(trials.count)
        }
        let manager = UploadManager(client: mock, queue: .disabled, enabled: true, rngSeed: 0x5555)
        let meta = sampleMeta()
        let results = sampleResults()
        let trials = (1...23).map { index -> Trial in
            Trial(
                trialIndex: index,
                block: .sst,
                type: index % 2 == 0 ? .go : .stop,
                direction: index % 3 == 0 ? .left : .right,
                goOnsetMs: 0,
                ssdMs: index % 2 == 0 ? nil : 100,
                rtMs: index % 2 == 0 ? 320 : nil,
                goSuccess: index % 2 == 0,
                stopSuccess: index % 2 != 0,
                gazeRMSEDeg: 0.6,
                viewingDistanceCm: 60,
                headMotionFlag: false,
                lostTrackingFlag: false,
                exclusions: []
            )
        }
        try await manager.upload(session: meta, results: results, trials: trials)
        XCTAssertEqual(batchSizes, [10, 10, 3])
    }

    func testBackoffRetriesOn429() async throws {
        let mock = MockUploadService()
        mock.sessionHandler = { _ in "recSession" }
        var attempt = 0
        mock.trialsHandler = { _, _ in
            attempt += 1
            if attempt < 3 {
                throw UploadError.httpStatus(429)
            }
        }
        let manager = UploadManager(client: mock, queue: .disabled, enabled: true, rngSeed: 0x42)
        let trials = [sampleTrial(index: 1, type: .stop)]
        try await manager.upload(session: sampleMeta(), results: sampleResults(), trials: trials)
        XCTAssertEqual(attempt, 3)
    }

    func testOfflineQueuePersistsAndDrains() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-test.json")
        try? FileManager.default.removeItem(at: tempURL)
        let queue = UploadQueue(storageURL: tempURL)
        let mock = MockUploadService()
        mock.sessionHandler = { _ in throw URLError(.notConnectedToInternet) }
        let manager = UploadManager(client: mock, queue: queue, enabled: true)
        let trials = [sampleTrial(index: 1, type: .go)]
        await XCTAssertThrowsErrorAsync(try await manager.upload(session: sampleMeta(), results: sampleResults(), trials: trials))
        XCTAssertEqual(queue.all().count, 1)
        mock.sessionHandler = { _ in "recSession" }
        mock.trialsHandler = { _, _ in }
        mock.resultsHandler = { _, _ in }
        try await manager.drain()
        XCTAssertEqual(queue.all().count, 0)
    }

    private func sampleMeta() -> SessionMeta {
        SessionMeta(
            sessionUID: UUID(),
            appVersion: "1.0",
            deviceModel: "Test",
            osVersion: "17.0",
            viewingDistanceMeanCm: 60,
            calibrationRMSEDeg: 1.0,
            ageBucket: .preferNotToSay,
            buildID: "1"
        )
    }

    private func sampleResults() -> Results {
        Results(
            baselineRTMs: 250,
            goRTMs: 320,
            goRTSlowingMs: 70,
            stoppingAccuracyPct: 90,
            ssrtMs: 200,
            pASDLike: 0.5,
            proactiveZ: 0,
            classificationLabel: .indeterminate,
            includedGo: 10,
            includedStop: 8,
            buildID: "1"
        )
    }

    private func sampleTrial(index: Int, type: TrialType) -> Trial {
        Trial(
            trialIndex: index,
            block: .sst,
            type: type,
            direction: .left,
            goOnsetMs: 0,
            ssdMs: type == .stop ? 100 : nil,
            rtMs: type == .go ? 300 : nil,
            goSuccess: type == .go,
            stopSuccess: type == .stop,
            gazeRMSEDeg: 0.6,
            viewingDistanceCm: 60,
            headMotionFlag: false,
            lostTrackingFlag: false,
            exclusions: []
        )
    }
}

private final class MockUploadService: UploadService {
    var sessionHandler: (([String: Any]) async throws -> String)?
    var trialsHandler: ((String, [[String: Any]]) async throws -> Void)?
    var resultsHandler: ((String, [String: Any]) async throws -> Void)?

    func createSession(_ fields: [String : Any]) async throws -> String {
        if let handler = sessionHandler {
            return try await handler(fields)
        }
        return "rec-default"
    }

    func createTrials(sessionRecordId: String, trials: [[String : Any]]) async throws {
        if let handler = trialsHandler {
            try await handler(sessionRecordId, trials)
        }
    }

    func createResults(sessionRecordId: String, fields: [String : Any]) async throws {
        if let handler = resultsHandler {
            try await handler(sessionRecordId, fields)
        }
    }
}

extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            // Expected
        }
    }
}
