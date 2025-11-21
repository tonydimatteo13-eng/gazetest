import SwiftUI
import FireFlyCore
import SpriteKit

struct GameContainerView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: coordinator.scene, options: [.allowsTransparency])
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                if showDirections {
                    Text(stageTitle)
                        .font(.headline)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                    Text(stageInstruction)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                }
                if let progress = progressPrimary {
                    Text(progress)
                        .font(.subheadline.bold())
                        .padding(8)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(10)
                }
                if let detail = progressDetail {
                    Text(detail)
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(10)
                }
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
            if showStartButton {
                VStack {
                    Spacer()
                    Button(startButtonLabel) {
                        coordinator.startCurrentStage()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var stageTitle: String {
        switch coordinator.stage {
        case .training:
            return "Practice"
        case .baseline:
            return "Baseline"
        case .sst:
            return "Stop-Signal"
        case .calibration:
            return "Calibration"
        default:
            return ""
        }
    }

    private var showDirections: Bool {
        !coordinator.stageStarted
    }

    private var showStartButton: Bool {
        requiresManualStart && !coordinator.stageStarted
    }

    private var startButtonLabel: String {
        switch coordinator.stage {
        case .training: return "Start practice"
        case .baseline: return "Start Part 1"
        case .sst: return "Start Part 2"
        default: return "Start"
        }
    }

    private var requiresManualStart: Bool {
        switch coordinator.stage {
        case .training, .baseline, .sst:
            return true
        default:
            return false
        }
    }

    private var stageInstruction: String {
        switch coordinator.stage {
        case .training:
            return "Practice round: keep your eyes on the owl. Follow the firefly quickly, and if a STOP sign appears, keep looking at the owl."
        case .baseline:
            return "Keep your eyes on the owl in the center. When the firefly appears, look at it as quickly as you can."
        case .sst:
            return "Keep your eyes on the owl. Look at the firefly quickly, but if a STOP sign appears, try not to look at the firefly."
        case .calibration:
            return "Keep your face in view and follow the star with your gaze until it moves to the next position."
        default:
            return ""
        }
    }

    private var progressPrimary: String? {
        switch coordinator.stage {
        case .training:
            return "Practice fireflies \(trainingCompleted) / \(trainingTarget)"
        case .baseline:
            return "Part 1: Fireflies \(baselineCompleted) / \(coordinator.config.baselineTrialCount)"
        case .sst:
            return "Forest fireflies \(sstCompleted) / 40+"
        default:
            return nil
        }
    }

    private var progressDetail: String? {
        switch coordinator.stage {
        case .sst:
            return "Valid GO \(sstValidGo) / 20 • Valid STOP \(sstValidStop) / 16"
        default:
            return nil
        }
    }

    private var trainingTarget: Int {
        coordinator.config.trainingGoCount + coordinator.config.trainingStopCount
    }

    private var trainingCompleted: Int {
        coordinator.trials.filter { $0.block == .training }.count
    }

    private var baselineCompleted: Int {
        coordinator.trials.filter { $0.block == .baseline }.count
    }

    private var sstCompleted: Int {
        coordinator.trials.filter { $0.block == .sst }.count
    }

    private var sstValidGo: Int {
        coordinator.trials.filter { isValidTrial($0) && $0.block == .sst && $0.type == .go && $0.goSuccess }.count
    }

    private var sstValidStop: Int {
        coordinator.trials.filter { isValidTrial($0) && $0.block == .sst && $0.type == .stop }.count
    }

    private func isValidTrial(_ trial: Trial) -> Bool {
        guard trial.block != .training else { return false }
        guard !trial.headMotionFlag, !trial.lostTrackingFlag else { return false }
        if trial.gazeRMSEDeg > 2.5 { return false }
        if let rt = trial.rtMs, rt < coordinator.config.anticipationThresholdMs { return false }
        if trial.type == .go && !trial.goSuccess { return false }
        return true
    }
}
