import SwiftUI

struct AuthenticationView: View {
    @State private var model = AuthenticationPresentationModel()

    var body: some View {
        let copy = model.presentation(for: model.state)

        ContentUnavailableView(
            copy.title,
            systemImage: "lock",
            description: Text(copy.message)
        )
        .padding()
    }
}
