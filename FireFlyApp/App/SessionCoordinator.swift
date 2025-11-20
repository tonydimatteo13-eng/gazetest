import Foundation
import Combine
import SwiftUI
import FireFlyCore
import SpriteKit
import UIKit

@MainActor
final class SessionCoordinator: ObservableObject {
    enum Stage {
        case welcome
        case calibration
        case baseline
        case sst
        case results
    }

    @Published var stage: Stage = .welcome
    @Published var calibrationRMSE: Double = 0
    @Published var trials: [Trial] = []
    @Published var results: Results?
    @Published var showAbout = false
    @Published var showPrivacy = false
    @Published var isUploading = false
    @Published var uploadStatus: String?
    @Published var gazeDebug: String = ""

    let gazeTracker: GazeTracker
    let calibrator = Calibrator()
    let scene = FireFlyScene(size: CGSize(width: 1024, height: 768))
    let config: GameConfig

    private(set) var sessionMeta: SessionMeta?
    @Published var calibrationController: CalibrationController?
    private var cancellables: Set<AnyCancellable> = []
    private let uploadManager: UploadManager

    init(
        config: GameConfig = .production,
        uploadManager: UploadManager = UploadManager.disabled
    ) {
        self.config = config
        self.uploadManager = uploadManager
        self.gazeTracker = GazeTracker()
        self.gazeTracker.onDebugMessage = { [weak self] message in
            Task { @MainActor in self?.gazeDebug = message }
        }
        scene.scaleMode = .aspectFill
        scene.onTrialFinished = { [weak self] trial in
            Task { await self?.handleTrial(trial) }
        }
    }

    func startSession() {
        trials.removeAll()
        results = nil
        calibrationRMSE = 0
        sessionMeta = nil
        gazeDebug = "Tracker: \(gazeTracker.modeDescription)"
        gazeTracker.start()
        stage = .calibration
        beginCalibration()
    }

    func beginCalibration() {
        let controller = CalibrationController(calibrator: calibrator, gazeTracker: gazeTracker)
        calibrationController = controller
        controller.onCompletion = { [weak self] result in
            Task { await self?.handleCalibration(result: result) }
        }
        controller.start()
    }

    func handleCalibration(result: CalibrationResult) async {
        calibrationRMSE = result.rmseDeg
        gazeTracker.apply(calibration: result)
        createSessionMeta()
        scene.configure(with: config, calibrator: calibrator, gaze: gazeTracker)
        calibrationController = nil
        stage = .baseline
        scene.startBaseline()
    }

    func handleTrial(_ trial: Trial) async {
        await MainActor.run {
            trials.append(trial)
            self.refreshSessionMeta()
        }
        let baselineCount = trials.filter { $0.block == .baseline }.count
        if stage == .baseline && baselineCount >= config.baselineTrialCount {
            await MainActor.run {
                stage = .sst
                scene.startSST()
            }
        }
        let sstCount = trials.filter { $0.block == .sst }.count
        if sstCount >= config.sstTrialCount {
            gazeTracker.stop()
            await finalizeResults()
        }
    }

    private func finalizeResults() async {
        guard let meta = sessionMeta else { return }
        let scored = Scorer.computeResults(session: meta, trials: trials)
        await MainActor.run {
            results = scored
            stage = .results
        }
    }

    private func refreshSessionMeta() {
        guard let meta = sessionMeta else { return }
        let distance = trials.map { $0.viewingDistanceCm }.average
        sessionMeta = SessionMeta(
            sessionUID: meta.sessionUID,
            appVersion: meta.appVersion,
            deviceModel: meta.deviceModel,
            osVersion: meta.osVersion,
            viewingDistanceMeanCm: distance,
            calibrationRMSEDeg: calibrationRMSE,
            ageBucket: meta.ageBucket,
            buildID: meta.buildID
        )
    }

    private func createSessionMeta() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let device = UIDevice.current.model
        let os = UIDevice.current.systemVersion
        let distanceMean = trials.map { $0.viewingDistanceCm }.average
        let meta = SessionMeta(
            sessionUID: UUID(),
            appVersion: version,
            deviceModel: device,
            osVersion: os,
            viewingDistanceMeanCm: distanceMean,
            calibrationRMSEDeg: calibrationRMSE,
            ageBucket: .preferNotToSay,
            buildID: build
        )
        sessionMeta = meta
    }

    func restart() {
        trials.removeAll()
        results = nil
        stage = .welcome
    }

    func upload() async {
        guard let meta = sessionMeta, let scored = results else { return }
        isUploading = true
        uploadStatus = "Preparing data…"
        do {
            try await uploadManager.upload(session: meta, results: scored, trials: trials)
            uploadStatus = "Upload complete"
        } catch {
            uploadStatus = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
    }
}

// MARK: - Helpers
private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
