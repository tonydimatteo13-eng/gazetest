import SwiftUI
import FireFlyCore

struct ResultsView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Text("Results")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("These numbers describe how quickly you looked at the firefly and how well you stopped when the STOP sign appeared. They are research-only and not a medical diagnosis.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.9))
            if let results = coordinator.results {
                ResultRow(title: "Baseline RT", value: format(ms: results.baselineRTMs))
                ResultRow(title: "GO RT", value: format(ms: results.goRTMs))
                ResultRow(title: "GO-RT Slowing", value: format(ms: results.goRTSlowingMs))
                ResultRow(title: "Stopping Accuracy", value: String(format: "%.1f%%", results.stoppingAccuracyPct))
                ResultRow(title: "SSRT", value: format(ms: results.ssrtMs))
                ResultRow(title: "Proactive Control z", value: String(format: "%.2f", results.proactiveZ))
                ResultRow(title: "ASD-likeness", value: String(format: "%.2f (%@)", results.pASDLike, results.classificationLabel.rawValue))
            }
            if coordinator.isUploading {
                ProgressView(coordinator.uploadStatus ?? "Uploading…")
                    .progressViewStyle(.circular)
                    .foregroundColor(.white)
            } else {
                Button("Export to Airtable") {
                    Task { await coordinator.upload() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Restart") {
                coordinator.restart()
            }
            .buttonStyle(.bordered)
            Button("About") {
                coordinator.showAbout = true
            }
            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }

    private func format(ms: Double) -> String {
        guard ms.isFinite else { return "–" }
        return String(format: "%.0f ms", ms)
    }
}

private struct ResultRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .bold()
                .foregroundColor(.white)
        }
    }
}
