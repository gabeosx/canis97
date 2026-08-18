import SwiftUI
import SiriusXMClient

struct AuthenticationView: View {
    @State private var model: AuthenticationPresentationModel
    @State private var bridge: WebAuthenticationBridge

    init() {
        let bridge = WebAuthenticationBridge()
        let client = SiriusXMClient(
            credentialSource: bridge,
            credentialStore: KeychainCredentialStore(),
            residueCleaner: bridge
        )
        _bridge = State(initialValue: bridge)
        _model = State(initialValue: AuthenticationPresentationModel(
            flow: ComposedAuthenticationPresentationFlow(bridge: bridge, client: client)
        ))
    }

    var body: some View {
        let copy = model.presentation(for: model.state)

        Group {
            if case .unsupported = model.state {
                VStack(alignment: .leading, spacing: 16) {
                    UnsupportedAuthenticationView(copy: copy)
                    HStack {
                        Button("Retry Sign In") { _ = model.retry() }
                        clearLocalSessionButton
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Label(copy.title, systemImage: copy.iconName)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)

                    Text(copy.message)
                        .foregroundStyle(.secondary)

                    if isVerifying {
                        ProgressView()
                            .accessibilityLabel("Authentication in progress")
                    } else if copy.isReady {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Authentication is complete", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                            Button("Sign Out") { _ = model.signOut() }
                        }
                    } else {
                        WebViewAuthenticationContainer(bridge: bridge)
                        authenticationActions
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .disabled(model.isAttemptInFlight)
        .padding()
    }

    private var isVerifying: Bool {
        switch model.state {
        case .verifyingAuthentication, .verifyingEntitlement:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var authenticationActions: some View {
        switch model.state {
        case .waitingForWebView:
            HStack {
                Button("Sign In") {
                    _ = model.signIn()
                }
                Button("Use Logged-In Session") {
                    _ = model.useLoggedInSession()
                }
                clearLocalSessionButton
            }
        case .authenticatedButNotEntitled,
             .rejected,
             .challengeRequired,
             .signedOut,
             .cleanupFailed:
            HStack {
                Button("Retry Sign In") { _ = model.retry() }
                clearLocalSessionButton
            }
        case .verifyingAuthentication,
             .verifyingEntitlement,
             .entitled,
             .unsupported:
            EmptyView()
        }
    }

    private var clearLocalSessionButton: some View {
        Button("Clear Local Session") { _ = model.clearLocalSession() }
    }
}

/// The fixed native location where Plan 01-06 attaches the nonpersistent WebKit bridge.
private struct WebViewAuthenticationContainer: View {
    let bridge: WebAuthenticationBridge

    var body: some View {
        GroupBox("Native sign-in") {
            WebAuthenticationView(bridge: bridge)
                .frame(maxWidth: .infinity, minHeight: 180)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Native SiriusXM sign-in area")
    }
}
