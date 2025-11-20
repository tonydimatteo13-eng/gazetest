import Foundation

public final class UploadManager {
    public static let disabled = UploadManager(client: DisabledUploadService(), queue: .disabled, enabled: false)

    private let client: UploadService
    private let queue: UploadQueue
    private let enabled: Bool
    private var rng: SeededGenerator

    public init(client: UploadService, queue: UploadQueue, enabled: Bool = true, rngSeed: UInt64 = 0x1BADB002) {
        self.client = client
        self.queue = queue
        self.enabled = enabled
        self.rng = SeededGenerator(seed: rngSeed)
    }

    public func upload(session: SessionMeta, results: Results, trials: [Trial]) async throws {
        guard enabled else { throw UploadError.disabled }
        let package = UploadPackage(id: UUID(), session: session, trials: trials, results: results)
        queue.enqueue(package)
        try await drain()
    }

    public func drain() async throws {
        guard enabled else { return }
        while let package = queue.peek() {
            do {
                try await transmit(package)
                _ = queue.pop()
            } catch UploadError.httpStatus(let code) where code == 429 {
                throw UploadError.httpStatus(code)
            } catch {
                throw error
            }
        }
    }

    private func transmit(_ package: UploadPackage) async throws {
        let sessionFields = sessionDictionary(from: package.session)
        let sessionRecordId = try await runWithRetry {
            try await self.client.createSession(sessionFields)
        }
        try await sendTrials(trials: package.trials, sessionId: sessionRecordId)
        let resultFields = resultsDictionary(from: package.results)
        try await runWithRetry {
            try await self.client.createResults(sessionRecordId: sessionRecordId, fields: resultFields)
        }
    }

    private func sendTrials(trials: [Trial], sessionId: String) async throws {
        guard !trials.isEmpty else { return }
        let chunkSize = 10
        var index = 0
        while index < trials.count {
            let chunk = Array(trials[index..<min(index + chunkSize, trials.count)])
            index += chunkSize
            let payload = chunk.map(trialDictionary)
            try await runWithRetry {
                try await self.client.createTrials(sessionRecordId: sessionId, trials: payload)
            }
        }
    }

    private func runWithRetry<T>(operation: @escaping () async throws -> T) async throws -> T {
        var delay: Double = 0.5
        let maxDelay: Double = 30.0
        let maxAttempts = 6
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch UploadError.httpStatus(let code) where code == 429 {
                attempt += 1
                guard attempt < maxAttempts else { throw UploadError.httpStatus(code) }
                let jitter = Double(rng.next()) / Double(UInt64.max) * 0.25
                let sleepTime = min(delay + jitter, maxDelay)
#if TESTMODE
                try await Task.sleep(nanoseconds: 1_000_000)
#else
                try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
#endif
                delay = min(delay * 2.0, maxDelay)
            } catch {
                throw error
            }
        }
    }

    private func sessionDictionary(from session: SessionMeta) -> [String: Any] {
        [
            "session_uid": session.sessionUID.uuidString,
            "app_version": session.appVersion,
            "device_model": session.deviceModel,
            "os_version": session.osVersion,
            "viewing_distance_mean_cm": session.viewingDistanceMeanCm,
            "calibration_rmse_deg": session.calibrationRMSEDeg,
            "age_bucket": session.ageBucket.rawValue,
            "build_id": session.buildID
        ]
    }

    private func trialDictionary(_ trial: Trial) -> [String: Any] {
        var dict: [String: Any] = [
            "trial_index": trial.trialIndex,
            "block": trial.block.rawValue,
            "type": trial.type.rawValue,
            "dir": trial.direction.rawValue,
            "go_onset_ms": trial.goOnsetMs,
            "go_success": trial.goSuccess ? 1 : 0,
            "stop_success": trial.stopSuccess ? 1 : 0,
            "gaze_rmse_deg": trial.gazeRMSEDeg,
            "viewing_distance_cm": trial.viewingDistanceCm,
            "head_motion_flag": trial.headMotionFlag ? 1 : 0,
            "lost_tracking_flag": trial.lostTrackingFlag ? 1 : 0
        ]
        if let ssd = trial.ssdMs { dict["ssd_ms"] = ssd }
        if let rt = trial.rtMs { dict["rt_ms"] = rt }
        if !trial.exclusions.isEmpty {
            dict["exclusions"] = trial.exclusions.map { $0.rawValue }
        }
        return dict
    }

    private func resultsDictionary(from results: Results) -> [String: Any] {
        [
            "baseline_rt_ms": results.baselineRTMs,
            "go_rt_sst_ms": results.goRTMs,
            "go_rt_slowing_ms": results.goRTSlowingMs,
            "stop_accuracy_pct": results.stoppingAccuracyPct,
            "ssrt_ms": results.ssrtMs,
            "p_asd_like": results.pASDLike,
            "proactive_z": results.proactiveZ,
            "classification_label": results.classificationLabel.rawValue,
            "included_go": results.includedGo,
            "included_stop": results.includedStop,
            "build_id": results.buildID
        ]
    }
}

private struct DisabledUploadService: UploadService {
    func createSession(_ fields: [String : Any]) async throws -> String {
        throw UploadError.disabled
    }
    func createTrials(sessionRecordId: String, trials: [[String : Any]]) async throws {
        throw UploadError.disabled
    }
    func createResults(sessionRecordId: String, fields: [String : Any]) async throws {
        throw UploadError.disabled
    }
}
