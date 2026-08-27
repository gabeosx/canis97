/// The app-owned brand registry. Provider-facing terminology remains outside this type.
enum ProductIdentity {
    static let displayName = "Rove"
    static let appTypeName = "RoveApp"
    static let targetName = "Rove"
    static let moduleName = "Rove"
    static let executableName = "Rove"
    static let appBundleIdentifier = "com.rove.player"
    static let unitTestTargetName = "RoveTests"
    static let unitTestBundleIdentifier = "com.rove.player.tests"
    static let uiTestTargetName = "RoveUITests"
    static let uiTestBundleIdentifier = "com.rove.player.uitests"
    static let schemeName = "Rove"
    static let uiValidationSchemeName = "RoveUIValidation"
    static let skinPackageTypeIdentifier = "com.rove.skin-package"
    static let skinPackageExtension = "roveskin"
    static let applicationSupportDirectoryName = "Rove"
    static let appLogSubsystem = "com.rove.player"
    static let environmentPrefix = "ROVE"
    static let scriptPrefix = "rove"
    static let compactSceneID = "rove-compact"
    static let librarySceneID = "rove-library"
    static let authenticationFrameAutosaveName = "Rove.authentication.frame"
    static let compactFrameAutosaveName = "Rove.compact.frame"
    static let libraryFrameAutosaveName = "Rove.library.frame"
    static let iconBasename = "ProductIcon"
    static let iconConcept = "Orbital Signal: a text-free layered midnight-blue disc, offset warm signal arcs, and a small luminous core. The geometry evokes a compact music device and visualizer without copying a provider mark, hardware silhouette, standard control, or another player's trade dress."
    static let nonAffiliationStatement = "Rove is an independent app and is not affiliated with, endorsed by, or sponsored by Sirius XM Radio LLC."

    enum SceneID {
        static let compact = ProductIdentity.compactSceneID
        static let library = ProductIdentity.librarySceneID
    }

    enum FrameAutosaveName {
        static let authentication = ProductIdentity.authenticationFrameAutosaveName
        static let compact = ProductIdentity.compactFrameAutosaveName
        static let library = ProductIdentity.libraryFrameAutosaveName
    }

    /// Read-only compatibility names for app-owned, non-secret state.
    /// This namespace intentionally exposes no Keychain migration operation.
    enum Legacy {
        static let applicationSupportDirectoryName = "Sirius Mac"
        static let skinPackageTypeIdentifier = "com.siriusmac.skin-package"
        static let skinPackageExtension = "siriusskin"
        static let appLogSubsystem = "com.siriusmac.player"
        static let compactSceneID = "sirius-compact"
        static let librarySceneID = "sirius-library"
        static let authenticationFrameAutosaveName = "SiriusMac.authentication.frame"
        static let compactFrameAutosaveName = "SiriusMac.compact.frame"
        static let libraryFrameAutosaveName = "SiriusMac.library.frame"
        static let keychainServiceCompatibilityValue = "com.siriusmac.player"
    }
}
