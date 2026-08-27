/// The app-owned brand registry. Provider-facing terminology remains outside this type.
enum ProductIdentity {
    static let displayName = "Modulune"
    static let appTypeName = "ModuluneApp"
    static let targetName = "Modulune"
    static let moduleName = "Modulune"
    static let executableName = "Modulune"
    static let appBundleIdentifier = "com.modulune.player"
    static let unitTestTargetName = "ModuluneTests"
    static let unitTestBundleIdentifier = "com.modulune.player.tests"
    static let uiTestTargetName = "ModuluneUITests"
    static let uiTestBundleIdentifier = "com.modulune.player.uitests"
    static let schemeName = "Modulune"
    static let uiValidationSchemeName = "ModuluneUIValidation"
    static let skinPackageTypeIdentifier = "com.modulune.skin-package"
    static let skinPackageExtension = "moduluneskin"
    static let applicationSupportDirectoryName = "Modulune"
    static let appLogSubsystem = "com.modulune.player"
    static let environmentPrefix = "MODULUNE"
    static let scriptPrefix = "modulune"
    static let compactSceneID = "modulune-compact"
    static let librarySceneID = "modulune-library"
    static let authenticationFrameAutosaveName = "Modulune.authentication.frame"
    static let compactFrameAutosaveName = "Modulune.compact.frame"
    static let libraryFrameAutosaveName = "Modulune.library.frame"
    static let iconBasename = "ProductIcon"
    static let iconConcept = "Orbital Signal: a text-free layered midnight-blue disc, offset warm signal arcs, and a small luminous core. The geometry evokes a compact music device and visualizer without copying a provider mark, hardware silhouette, standard control, or another player's trade dress."
    static let nonAffiliationStatement = "Modulune is an independent app and is not affiliated with, endorsed by, or sponsored by Sirius XM Radio LLC."

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
