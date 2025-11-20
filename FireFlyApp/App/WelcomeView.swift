import SwiftUI
import FireFlyCore
import SpriteKit

struct RootView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch coordinator.stage {
            case .welcome:
                WelcomeView()
            case .calibration:
                CalibrationView()
            case .baseline, .sst:
                GameContainerView()
            case .results:
                ResultsView()
            }
        }
        .sheet(isPresented: $coordinator.showAbout) {
            AboutView()
        }
        .sheet(isPresented: $coordinator.showPrivacy) {
            PrivacyView()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Welcome to FireFly")
                    .font(.largeTitle.bold())
                Text("Keep your face in view so the iPad can track your eyes.")
                Text("First you will practice by following the firefly. Then you will play a game where a STOP sign sometimes appears.")
                Text("Your job: look at the firefly as quickly as you can, but if a STOP sign appears, try not to look at the firefly.")
            }
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)

            VStack(spacing: 16) {
                Button("Start") {
                    coordinator.startSession()
                }
                .buttonStyle(.borderedProminent)

                Button("About the task") {
                    coordinator.showAbout = true
                }

                Button("Privacy") {
                    coordinator.showPrivacy = true
                }
            }
            Spacer()
            Text("Demo only. Not a diagnosis.")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding()
    }
}
