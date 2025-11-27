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
        case calibrationReview
        case training
        case baseline
        case baselineBreak
        case sst
        case sstMidBreak
        case results
    }

    enum CalibrationQuality {
        case good
        case ok
        case poor
    }

    @Published var stage: Stage = .welcome
    @Published var calibrationRMSE: Double = 0
    @Published var calibrationResult: CalibrationResult?
    @Published var calibrationQuality: CalibrationQuality?
    @Published var trials: [Trial] = []
    @Published var results: Results?
    @Published var showAbout = false
    @Published var showPrivacy = false
    @Published var isUploading = false
    @Published var uploadStatus: String?
    @Published var gazeDebug: String = ""
    @Published var stageStarted: Bool = false

    let gazeTracker: GazeTracker
    let calibrator = Calibrator()
    let scene = FireFlyScene(size: CGSize(width: 1024, height: 768))
    let config: GameConfig

    private(set) var sessionMeta: SessionMeta?
    @Published var calibrationController: CalibrationController?
    private var cancellables: Set<AnyCancellable> = []
    private let uploadManager: UploadManager
    private var pendingMidSSTResume = false

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
        scene.onBlockFinished = { [weak self] block in
            Task { await self?.handleBlockFinished(block) }
        }
        scene.onBreakRequested = { [weak self] type in
            Task { await self?.handleBreakRequest(type) }
        }
    }

    func startSession() {
        trials.removeAll()
        results = nil
        calibrationRMSE = 0
        calibrationResult = nil
        calibrationQuality = nil
        sessionMeta = nil
        gazeDebug = "Tracker: \(gazeTracker.modeDescription)"
        gazeTracker.start()
        stageStarted = false
        pendingMidSSTResume = false
        beginCalibration()
    }

    func beginCalibration() {
        stage = .calibration
        stageStarted = false
        calibrationResult = nil
        calibrationQuality = nil
        let controller = CalibrationController(calibrator: calibrator, gazeTracker: gazeTracker)
        calibrationController = controller
        controller.onCompletion = { [weak self] result in
            Task { await self?.handleCalibration(result: result) }
        }
        controller.start()
    }

    func handleCalibration(result: CalibrationResult) async {
        await MainActor.run {
            calibrationRMSE = result.rmseDeg
            calibrationResult = result
            calibrationQuality = quality(for: result.rmseDeg)
            gazeTracker.apply(calibration: result)
            calibrationController = nil
            stage = .calibrationReview
        }
    }

    func continueAfterCalibration() {
        guard calibrationResult != nil, let quality = calibrationQuality else { return }
        guard quality != .poor else { return }
        createSessionMeta()
        scene.configure(with: config, calibrator: calibrator, gaze: gazeTracker, sessionUID: sessionMeta?.sessionUID)
        stage = .training
        stageStarted = false
    }

    func continueToSST() {
        stage = .sst
        stageStarted = false
        pendingMidSSTResume = false
    }

    func resumeAfterMidSSTBreak() {
        pendingMidSSTResume = true
        stage = .sst
        stageStarted = false
    }

    func requestRecalibration() {
        beginCalibration()
    }

    func handleTrial(_ trial: Trial) async {
        await MainActor.run {
            trials.append(trial)
            self.refreshSessionMeta()
        }
    }

    func handleBlockFinished(_ block: TrialBlock) async {
        switch block {
        case .training:
            await MainActor.run {
                stage = .baseline
                stageStarted = false
            }
        case .baseline:
            await MainActor.run {
                stage = .baselineBreak
                stageStarted = false
            }
        case .sst:
            gazeTracker.stop()
            await finalizeResults()
        }
    }

    func handleBreakRequest(_ breakType: FireFlyScene.BreakType) async {
        switch breakType {
        case .baselineToSST:
            await MainActor.run {
                stage = .baselineBreak
                stageStarted = false
            }
        case .midSST:
            await MainActor.run {
                stage = .sstMidBreak
                stageStarted = false
                pendingMidSSTResume = true
                print("[SessionCoordinator] Mid-SST break requested")
            }
        }
    }

    func startCurrentStage() {
        guard !stageStarted else { return }
        switch stage {
        case .training:
            stageStarted = true
            scene.startTraining()
        case .baseline:
            stageStarted = true
            scene.startBaseline()
        case .sst:
            stageStarted = true
            if pendingMidSSTResume {
                pendingMidSSTResume = false
                print("[SessionCoordinator] Resuming SST after mid-block break")
                scene.resumeAfterBreak()
            } else {
                scene.startSST()
            }
        default:
            break
        }
    }

    private func finalizeResults() async {
        guard let meta = sessionMeta else { return }
        let scored = Scorer.computeResults(session: meta, trials: trials, config: config)
        logSessionSummary(trials: trials)
        await MainActor.run {
            print("[SessionCoordinator] results – baselineGo=\(scored.includedBaselineGo) sstGo=\(scored.includedSSTGo) stop=\(scored.includedStop) includedGoAll=\(scored.includedGo)")
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

    private func logSessionSummary(trials: [Trial]) {
        let baselineGo = trials.filter { $0.block == .baseline && $0.type == .go }
        let sstGo = trials.filter { $0.block == .sst && $0.type == .go }
        let sstStop = trials.filter { $0.block == .sst && $0.type == .stop }
        let baselineValid = baselineGo.filter { TrialEngine.isIncluded($0, config: config) }.count
        let sstGoValid = sstGo.filter { TrialEngine.isIncluded($0, config: config) }.count
        let sstStopValid = sstStop.filter { TrialEngine.isIncluded($0, config: config) }.count

        let baselineReasons = formatBreakdown(exclusionBreakdown(for: baselineGo))
        let sstGoReasons = formatBreakdown(exclusionBreakdown(for: sstGo))
        let sstStopReasons = formatBreakdown(exclusionBreakdown(for: sstStop))

        let baselinePart = "[SessionSummary] baseline: validGo=\(baselineValid)/\(baselineGo.count)\(baselineReasons.isEmpty ? "" : " \(baselineReasons)")"
        let sstPart = "sst: validGo=\(sstGoValid)/\(sstGo.count)\(sstGoReasons.isEmpty ? "" : " \(sstGoReasons)") validStop=\(sstStopValid)/\(sstStop.count)\(sstStopReasons.isEmpty ? "" : " \(sstStopReasons)")"
        print("\(baselinePart) \(sstPart)")
    }

    private func exclusionBreakdown(for trials: [Trial]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for trial in trials {
            for exclusion in trial.exclusions {
                counts[exclusion.debugLabel, default: 0] += 1
            }
            if trial.type == .go && !trial.goSuccess && !trial.exclusions.contains(.noCorridorEntry) {
                counts[TrialExclusion.noCorridorEntry.debugLabel, default: 0] += 1
            }
        }
        return counts
    }

    private func formatBreakdown(_ counts: [String: Int]) -> String {
        let preferredOrder = ["noCorridorEntry", "anticipation", "highRMSE", "headMotion", "lostTracking", "timeout"]
        var parts: [String] = preferredOrder.compactMap { key in
            guard let value = counts[key], value > 0 else { return nil }
            return "\(key)=\(value)"
        }
        let remaining = counts.filter { !preferredOrder.contains($0.key) && $0.value > 0 }
        parts.append(contentsOf: remaining.map { "\($0.key)=\($0.value)" }.sorted())
        guard !parts.isEmpty else { return "" }
        return "(\(parts.joined(separator: ", ")))"
    }

    private func quality(for rmse: Double) -> CalibrationQuality {
        if rmse <= 1.5 { return .good }
        if rmse <= 2.0 { return .ok }
        return .poor
    }

    func restart() {
        trials.removeAll()
        results = nil
        stage = .welcome
        pendingMidSSTResume = false
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
