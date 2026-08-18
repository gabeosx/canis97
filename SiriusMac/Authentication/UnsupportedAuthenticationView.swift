import SwiftUI

struct UnsupportedAuthenticationView: View {
    let copy: AuthenticationPresentationCopy

    var body: some View {
        ContentUnavailableView(
            copy.title,
            systemImage: copy.iconName,
            description: Text(copy.message)
        )
    }
}
