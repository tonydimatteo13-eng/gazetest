import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let controller = coordinator.calibrationController {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        StarView(controller: controller, size: proxy.size)
                        Text("Calibration")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Calibration")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    if let result = coordinator.calibrationResult, let quality = coordinator.calibrationQuality {
                        VStack(spacing: 6) {
                            Text(qualityLabel(for: quality))
                                .font(.title3.bold())
                                .foregroundColor(qualityColor(for: quality))
                            Text(String(format: "RMSE %.2f°", result.rmseDeg))
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(qualityMessage(for: quality))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                    }
                    if coordinator.calibrationResult != nil {
                        HStack(spacing: 16) {
                            Button("Recalibrate") {
                                coordinator.requestRecalibration()
                            }
                            .buttonStyle(.bordered)
                            Button("Continue") {
                                coordinator.continueAfterCalibration()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canContinue)
                            .opacity(canContinue ? 1 : 0.6)
                        }
                        .padding(.top, 12)
                    }
                }
                .padding()
            }
        }
    }

    private var canContinue: Bool {
        guard let quality = coordinator.calibrationQuality else { return false }
        return quality != .poor
    }

    private func qualityLabel(for quality: SessionCoordinator.CalibrationQuality) -> String {
        switch quality {
        case .good: return "Good calibration"
        case .ok: return "OK calibration"
        case .poor: return "Poor calibration"
        }
    }

    private func qualityMessage(for quality: SessionCoordinator.CalibrationQuality) -> String {
        switch quality {
        case .good:
            return "Looks sharp. You can continue to the game."
        case .ok:
            return "Signal is a bit fuzzy, you can recalibrate if needed."
        case .poor:
            return "Please recalibrate before starting."
        }
    }

    private func qualityColor(for quality: SessionCoordinator.CalibrationQuality) -> Color {
        switch quality {
        case .good: return .green
        case .ok: return .yellow
        case .poor: return .red
        }
    }
}

private struct StarView: View {
    @ObservedObject var controller: CalibrationController
    let size: CGSize

    var body: some View {
        let point = controller.currentPoint
        Image("star_calib")
            .resizable()
            .frame(width: 44, height: 44)
            .position(x: max(22, min(size.width - 22, point.x)),
                      y: max(22, min(size.height - 22, point.y)))
            .animation(.easeInOut(duration: 0.2), value: point)
    }
}
