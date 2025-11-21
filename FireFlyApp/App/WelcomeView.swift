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
            case .calibration, .calibrationReview:
                CalibrationView()
            case .training, .baseline, .sst:
                GameContainerView()
            case .baselineBreak, .sstMidBreak:
                BreakView()
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

struct BreakView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.ignoresSafeArea())
    }

    private var title: String {
        switch coordinator.stage {
        case .baselineBreak:
            return "Part 1 done!"
        case .sstMidBreak:
            return "Halfway there"
        default:
            return ""
        }
    }

    private var message: String {
        switch coordinator.stage {
        case .baselineBreak:
            return "Next, the owl may show a STOP sign. Follow the firefly unless you see STOP, then keep your eyes on the owl."
        case .sstMidBreak:
            return "Take a breath, then tap when you're ready for more fireflies."
        default:
            return ""
        }
    }

    private var buttonTitle: String {
        switch coordinator.stage {
        case .baselineBreak:
            return "Start Part 2"
        case .sstMidBreak:
            return "Keep Going"
        default:
            return "Continue"
        }
    }

    private func action() {
        switch coordinator.stage {
        case .baselineBreak:
            coordinator.continueToSST()
        case .sstMidBreak:
            coordinator.resumeAfterMidSSTBreak()
        default:
            break
        }
    }
}
