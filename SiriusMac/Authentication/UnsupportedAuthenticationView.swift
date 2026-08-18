import SwiftUI

struct UnsupportedAuthenticationView: View {
    let copy: AuthenticationPresentationCopy

    var body: some View {
        ContentUnavailableView(
            copy.title,
            systemImage: "exclamationmark.triangle",
            description: Text(copy.message)
        )
    }
}
