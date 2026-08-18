import SwiftUI

struct AuthenticationView: View {
    @State private var model = AuthenticationPresentationModel()

    var body: some View {
        let copy = model.presentation(for: model.state)

        Group {
            if case .unsupported = model.state {
                VStack(alignment: .leading, spacing: 16) {
                    UnsupportedAuthenticationView(copy: copy)
                    Button("Retry Sign In") { _ = model.retry() }
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
                        WebViewAuthenticationContainer()
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
                Button("Sign In") { _ = model.signIn() }
                Button("Use Logged-In Session") { _ = model.useLoggedInSession() }
            }
        case .authenticatedButNotEntitled,
             .rejected,
             .challengeRequired,
             .signedOut,
             .cleanupFailed:
            Button("Retry Sign In") { _ = model.retry() }
        case .verifyingAuthentication,
             .verifyingEntitlement,
             .entitled,
             .unsupported:
            EmptyView()
        }
    }
}

/// The fixed native location where Plan 01-06 attaches the nonpersistent WebKit bridge.
private struct WebViewAuthenticationContainer: View {
    var body: some View {
        GroupBox("Native sign-in") {
            Text("The SiriusXM sign-in page opens here when you choose Sign In.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Native SiriusXM sign-in area")
    }
}
