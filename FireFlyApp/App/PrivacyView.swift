import SwiftUI

struct PrivacyView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy")
                        .font(.title)
                    Text("FireFlyApp runs entirely on-device. We do not collect names, photos, or contact information. Each session is identified by a random UUID. Metrics are anonymous and can be exported only with your consent.")
                    Text("Camera access is used solely for gaze tracking via the TrueDepth sensor. Data never leaves the device unless you explicitly export it.")
                    Text("Demo only. Not a diagnosis.")
                }
                .padding()
            }
            .navigationTitle("Privacy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton()
                }
            }
        }
    }
}


private struct CloseButton: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Button("Close") {
            dismiss()
        }
    }
}
