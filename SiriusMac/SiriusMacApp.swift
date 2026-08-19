import Foundation
import SwiftUI

@main
struct SiriusMacApp: App {
    var body: some Scene {
        WindowGroup("Sirius Mac") {
            if SiriusMacLaunchMode.isUnitTestHost() {
                Color.clear
                    .frame(minWidth: 760, minHeight: 620)
                    .accessibilityHidden(true)
            } else {
                AuthenticationView()
                    .frame(minWidth: 760, minHeight: 620)
            }
        }
        .defaultSize(width: 1_160, height: 820)
        .windowResizability(.contentMinSize)
    }
}

/// The unit-test bundle uses the app executable as its host. Keep that host
/// intentionally inert so running tests cannot read, authenticate with, or
/// erase the production Keychain session.
enum SiriusMacLaunchMode {
    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
