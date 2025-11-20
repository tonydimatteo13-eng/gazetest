import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("About the Stop-Signal Task")
                    .font(.title)
                Text("• Track the firefly as quickly as possible when it appears.")
                Text("• If a STOP sign appears, keep your gaze on the owl.")
                Text("• Results estimate response control – demo only, not diagnostic.")
                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
