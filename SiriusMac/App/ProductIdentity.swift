/// The app-owned brand registry. Provider-facing terminology remains outside this type.
enum ProductIdentity {
    static let displayName = "Canis97"
    static let appTypeName = "Canis97App"
    static let targetName = "Canis97"
    static let moduleName = "Canis97"
    static let executableName = "Canis97"
    static let appBundleIdentifier = "com.canis97.player"
    static let unitTestTargetName = "Canis97Tests"
    static let unitTestBundleIdentifier = "com.canis97.player.tests"
    static let uiTestTargetName = "Canis97UITests"
    static let uiTestBundleIdentifier = "com.canis97.player.uitests"
    static let schemeName = "Canis97"
    static let schemeFileName = "Canis97.xcscheme"
    static let uiValidationSchemeName = "Canis97UIValidation"
    static let uiValidationSchemeFileName = "Canis97UIValidation.xcscheme"
    static let skinPackageTypeIdentifier = "com.canis97.skin-package"
    static let skinPackageExtension = "canis97skin"
    static let applicationSupportDirectoryName = "Canis97"
    static let appLogSubsystem = "com.canis97.player"
    static let environmentPrefix = "CANIS97"
    static let scriptPrefix = "canis97"
    static let compactSceneID = "canis97-compact"
    static let librarySceneID = "canis97-library"
    static let authenticationFrameAutosaveName = "Canis97.authentication.frame"
    static let compactFrameAutosaveName = "Canis97.compact.frame"
    static let libraryFrameAutosaveName = "Canis97.library.frame"
    static let iconBasename = "ProductIcon"
    static let iconConcept = "Orbital Signal: a text-free layered midnight-blue disc, offset warm signal arcs, and a small luminous core. Its abstract celestial signal language supports Canis97's Canis Major reference without dog imagery, provider marks, hardware silhouettes, standard controls, or another player's trade dress."
    static let nonAffiliationStatement = "Canis97 is an independent app and is not affiliated with, endorsed by, or sponsored by Sirius XM Radio LLC."

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
