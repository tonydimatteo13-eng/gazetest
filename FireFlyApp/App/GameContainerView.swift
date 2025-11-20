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
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
        }
    }

    private var stageTitle: String {
        switch coordinator.stage {
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

    private var stageInstruction: String {
        switch coordinator.stage {
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
}
