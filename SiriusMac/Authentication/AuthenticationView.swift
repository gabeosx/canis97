import SwiftUI

struct AuthenticationView: View {
    @State private var model = AuthenticationPresentationModel()

    var body: some View {
        let copy = model.presentation(for: model.state)

        Group {
            if case .unsupported = model.state {
                UnsupportedAuthenticationView(copy: copy)
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
                        Label("Authentication is complete", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        WebViewAuthenticationContainer()
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
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
