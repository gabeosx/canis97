import SwiftUI

@main
struct SiriusMacApp: App {
    var body: some Scene {
        WindowGroup("Sirius Mac") {
            AuthenticationView()
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 1_160, height: 820)
        .windowResizability(.contentMinSize)
    }
}
