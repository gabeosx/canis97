/// The app-owned brand registry. Provider-facing terminology remains outside this type.
enum ProductIdentity {
    static let displayName = "Bit Deck"
    static let appTypeName = "BitDeckApp"
    static let targetName = "BitDeck"
    static let moduleName = "BitDeck"
    static let executableName = "BitDeck"
    static let appBundleIdentifier = "com.bitdeck.player"
    static let unitTestTargetName = "BitDeckTests"
    static let unitTestBundleIdentifier = "com.bitdeck.player.tests"
    static let uiTestTargetName = "BitDeckUITests"
    static let uiTestBundleIdentifier = "com.bitdeck.player.uitests"
    static let schemeName = "BitDeck"
    static let uiValidationSchemeName = "BitDeckUIValidation"
    static let skinPackageTypeIdentifier = "com.bitdeck.skin-package"
    static let skinPackageExtension = "bitdeckskin"
    static let applicationSupportDirectoryName = "Bit Deck"
    static let appLogSubsystem = "com.bitdeck.player"
    static let environmentPrefix = "BITDECK"
    static let scriptPrefix = "bitdeck"
    static let compactSceneID = "bitdeck-compact"
    static let librarySceneID = "bitdeck-library"
    static let authenticationFrameAutosaveName = "BitDeck.authentication.frame"
    static let compactFrameAutosaveName = "BitDeck.compact.frame"
    static let libraryFrameAutosaveName = "BitDeck.library.frame"
    static let iconBasename = "ProductIcon"
    static let iconConcept = "Orbital Signal: a text-free layered midnight-blue disc, offset warm signal arcs, and a small luminous core. The geometry evokes a compact music device and spectrum visualizer without copying a provider mark, hardware silhouette, standard control, or another player's trade dress."
    static let nonAffiliationStatement = "Bit Deck is an independent app and is not affiliated with, endorsed by, or sponsored by Sirius XM Radio LLC."

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
