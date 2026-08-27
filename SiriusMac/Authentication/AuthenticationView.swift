import SwiftUI
import SiriusXMClient

struct AuthenticationView: View {
    let controller: ListeningSessionController

    private var model: AuthenticationPresentationModel { controller.authenticationModel }
    private var bridge: WebAuthenticationBridge { controller.bridge }
    var body: some View {
        SwiftUI.Group {
            if model.isReady {
                VStack(alignment: .leading, spacing: 12) {
                    ListeningView(controller: controller)
                    HStack {
                        Button("Sign Out") {
                            controller.resetListeningBeforeAuthenticationCleanup()
                            _ = model.signOut()
                        }
                        clearLocalSessionButton
                    }
                    .padding(.horizontal, 24)
                }
            } else {
                authenticationContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .disabled(model.isAttemptInFlight)
        .task { @MainActor in
            let attempt = model.restoreStoredCredentialOnLaunch()
            await attempt?.value
        }
    }

    private var authenticationContent: some View {
        let copy = model.presentation(for: model.state)
        return VStack(alignment: .leading, spacing: 16) {
            if case .unsupported = model.state {
                UnsupportedAuthenticationView(copy: copy)
                HStack {
                    Button("Retry Sign In") { _ = model.retry() }
                    clearLocalSessionButton
                }
            } else {
                Label(copy.title, systemImage: copy.iconName)
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)

                Text(copy.message)
                    .foregroundStyle(.secondary)

                if isVerifying {
                    ProgressView()
                        .accessibilityLabel("Authentication in progress")
                } else {
                    if model.state == .waitingForWebView {
                        WebViewAuthenticationContainer(bridge: bridge)
                    }
                    authenticationActions
                }
            }
        }
        .frame(maxWidth: AuthenticationLayout.maximumContentWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(AuthenticationLayout.contentPadding)
    }

    private var isVerifying: Bool {
        switch model.state {
        case .verifyingAuthentication, .verifyingEntitlement, .finishingCleanup: true
        default: false
        }
    }

    @ViewBuilder
    private var authenticationActions: some View {
        switch model.state {
        case .waitingForWebView:
            HStack {
                Button("Use This Window’s Session") { _ = model.useLoggedInSession() }
                clearLocalSessionButton
            }
        case .localCredentialInvalid,
             .localCredentialUnavailable,
             .webSessionResetFailed,
             .authenticatedButNotEntitled,
             .profileAuthorizationRejected,
             .entitlementAuthorizationRejected,
             .credentialNotDurable,
             .rejected,
             .challengeRequired,
             .cleanupFailed:
            HStack {
                Button("Retry Sign In") { _ = model.retry() }
                clearLocalSessionButton
            }
        case .localCredentialMissing, .signedOut:
            HStack {
                Button("Sign In") { _ = model.signIn() }
                clearLocalSessionButton
            }
        case .verifyingAuthentication,
             .verifyingEntitlement,
             .finishingCleanup,
             .entitled,
             .restoreCompleted,
             .unsupported:
            EmptyView()
        }
    }

    private var clearLocalSessionButton: some View {
        Button("Clear Local Session") {
            controller.resetListeningBeforeAuthenticationCleanup()
            _ = model.clearLocalSession()
        }
    }
}

/// Keeps production composition to one Keychain adapter, one WebView bridge,
/// and one client shared by authentication and semantic catalog browsing.
@MainActor
struct AuthenticationComposition {
    let bridge: WebAuthenticationBridge
    let keychain: KeychainCredentialStore
    let credentialSource: RestorableAuthenticationCredentialSource
    let flow: ComposedAuthenticationPresentationFlow
    let listeningFlow: any ListeningFlow
    let playbackCoordinator: PlaybackCoordinator

    init() {
        self.init(bridge: WebAuthenticationBridge(), keychain: KeychainCredentialStore())
    }

    init(
        bridge: WebAuthenticationBridge,
        keychain: KeychainCredentialStore,
        client: (any ClientAuthenticationFlow)? = nil,
        playbackCoordinator injectedPlaybackCoordinator: PlaybackCoordinator? = nil
    ) {
        let credentialSource = RestorableAuthenticationCredentialSource(keychain: keychain, webViewSource: bridge)

        self.bridge = bridge
        self.keychain = keychain
        self.credentialSource = credentialSource

        if let client {
            // Test-only composition remains closed: a non-SiriusXM fake cannot
            // acquire playback authority merely by satisfying auth presentation.
            self.flow = ComposedAuthenticationPresentationFlow(
                bridge: bridge,
                client: client,
                credentialSource: credentialSource
            )
            self.listeningFlow = (client as? any ListeningFlow) ?? UnavailableListeningFlow()
            self.playbackCoordinator = injectedPlaybackCoordinator ?? PlaybackCoordinator(resolver: UnavailablePlaybackResolver())
        } else {
            let composedClient = SiriusXMClient(
                credentialSource: credentialSource,
                credentialStore: keychain,
                residueCleaner: bridge
            )
            self.flow = ComposedAuthenticationPresentationFlow(
                bridge: bridge,
                client: composedClient,
                credentialSource: credentialSource
            )
            self.listeningFlow = composedClient
            self.playbackCoordinator = injectedPlaybackCoordinator ?? PlaybackCoordinator(
                resolver: SiriusXMPlaybackResolver(client: composedClient),
                networkObserver: SystemNetworkPathObserver(),
                workspaceObserver: SystemWorkspacePowerObserver()
            )
        }
    }
}

private final class UnavailableListeningFlow: ListeningFlow, @unchecked Sendable {
    func catalog() async -> CatalogAvailability { .failed(.unavailable) }
}

private struct UnavailablePlaybackResolver: PlaybackResolving {
    func resolve(for _: LiveChannelID) async -> PlaybackResourceResolution {
        .failed(.authorizationUnavailable)
    }
}

/// The fixed native location where the nonpersistent WebKit bridge is shown.
private struct WebViewAuthenticationContainer: View {
    let bridge: WebAuthenticationBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Native sign-in")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Text("\(ProductIdentity.displayName) connects to your SiriusXM subscriber account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Text(ProductIdentity.nonAffiliationStatement)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            WebAuthenticationView(bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: AuthenticationLayout.webViewCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AuthenticationLayout.webViewCornerRadius)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, minHeight: AuthenticationLayout.minimumWebViewHeight, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Native SiriusXM sign-in area")
    }
}

private enum AuthenticationLayout {
    static let contentPadding: CGFloat = 24
    static let maximumContentWidth: CGFloat = 1_200
    static let minimumWebViewHeight: CGFloat = 420
    static let webViewCornerRadius: CGFloat = 8
}
