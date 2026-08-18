import SwiftUI
import Observation
import SiriusXMClient

@main
struct SiriusMacApp: App {
    var body: some Scene {
        WindowGroup("Sirius Mac") {
            CompatibilityView()
        }
    }
}

@MainActor
@Observable
final class CompatibilityPresentationModel {
    private let client: SiriusXMClient

    private(set) var presentationCount = 0
    private(set) var backgroundRetryCount = 0

    init(client: SiriusXMClient = SiriusXMClient()) {
        self.client = client
    }

    func present() async -> CompatibilityPresentationState {
        presentationCount += 1

        switch await client.authenticationAvailability() {
        case .waitingForAuthenticationComposition:
            return .waitingForAuthenticationComposition
        case .authenticatedPendingEntitlement,
             .rejected,
             .challengeRequired,
             .unsupported,
             .cancelled:
            // This walking skeleton intentionally stays in its unavailable state
            // until Plan 01-05 installs the complete typed authentication UI.
            return .waitingForAuthenticationComposition
        }
    }
}

enum CompatibilityPresentationState: Equatable {
    case waitingForAuthenticationComposition
}

private struct CompatibilityView: View {
    @State private var model = CompatibilityPresentationModel()
    @State private var state: CompatibilityPresentationState?

    var body: some View {
        Group {
            switch state {
            case .waitingForAuthenticationComposition:
                ContentUnavailableView(
                    "Sign-in setup is not yet available",
                    systemImage: "lock",
                    description: Text("Sirius Mac is waiting for the native sign-in bridge.")
                )
            case nil:
                ProgressView("Preparing compatibility status…")
            }
        }
        .padding()
        .task {
            state = await model.present()
        }
    }
}
