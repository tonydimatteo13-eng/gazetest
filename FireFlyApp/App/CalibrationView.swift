import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("Calibration")
                    .font(.title2.bold())
                Text("Keep your face in view. Gently move only your eyes.")
                Text("When the star appears, look right at it and keep your eyes there until it moves to the next spot.")
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            if !coordinator.gazeDebug.isEmpty {
                Text(coordinator.gazeDebug)
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            if let controller = coordinator.calibrationController {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: controller.progress, total: 1)
                        .tint(.white)
                    Text(String(format: "Progress %.0f%%", controller.progress * 100))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal)
            }
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    if let controller = coordinator.calibrationController {
                        StarView(controller: controller, size: proxy.size)
                    }
                }
            }
            .padding()
            if let status = coordinator.calibrationController?.status {
                Text(status)
                    .foregroundColor(.white)
                    .padding(.top, 8)
                if let debug = coordinator.calibrationController?.debugInfo, !debug.isEmpty {
                    Text(debug)
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
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
