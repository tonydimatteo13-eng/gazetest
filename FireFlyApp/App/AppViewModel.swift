import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isTestMode: Bool

    init() {
        #if TESTMODE
        isTestMode = true
        #else
        isTestMode = false
        #endif
    }
}
