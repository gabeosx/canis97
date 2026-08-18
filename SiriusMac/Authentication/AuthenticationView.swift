import SwiftUI
import SiriusXMClient

struct AuthenticationView: View {
    @State private var model: AuthenticationPresentationModel
    @State private var bridge: WebAuthenticationBridge

    init() {
        let composition = AuthenticationComposition()
        _bridge = State(initialValue: composition.bridge)
        _model = State(initialValue: AuthenticationPresentationModel(
            flow: composition.flow
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

/// Keeps production composition to one Keychain adapter, one WebView bridge, and
/// one combined credential source. Tests can recreate the same graph with fakes.
@MainActor
struct AuthenticationComposition {
    let bridge: WebAuthenticationBridge
    let credentialSource: RestorableAuthenticationCredentialSource
    let flow: ComposedAuthenticationPresentationFlow

    init() {
        self.init(bridge: WebAuthenticationBridge(), keychain: KeychainCredentialStore())
    }

    init(
        bridge: WebAuthenticationBridge,
        keychain: KeychainCredentialStore,
        client: (any ClientAuthenticationFlow)? = nil
    ) {
        let credentialSource = RestorableAuthenticationCredentialSource(
            keychain: keychain,
            webViewSource: bridge
        )
        let composedClient = client ?? SiriusXMClient(
            credentialSource: credentialSource,
            credentialStore: keychain,
            residueCleaner: bridge
        )

        self.bridge = bridge
        self.credentialSource = credentialSource
        flow = ComposedAuthenticationPresentationFlow(
            bridge: bridge,
            client: composedClient,
            credentialSource: credentialSource
        )
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
