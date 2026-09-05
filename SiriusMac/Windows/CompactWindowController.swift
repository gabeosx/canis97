@preconcurrency import AppKit
import SwiftUI

/// The native window policies available to the authentication and listening shell.
/// Renderers and user data cannot select another role or change close semantics.
enum WindowRole: CaseIterable {
    case authentication
    case compact
    case library
}

enum WindowLevel: Equatable {
    case normal
    case floating
}

@MainActor
protocol ApplicationTerminating: AnyObject {
    func requestTermination()
}

@MainActor
final class NSApplicationTerminator: ApplicationTerminating {
    func requestTermination() {
        NSApp.terminate(nil)
    }
}

/// Platform-independent policy for the narrow window bridge. Keeping the
/// decisions here makes lifecycle behavior testable without creating windows.
@MainActor
final class WindowLifecyclePolicy {
    let role: WindowRole
    private let terminator: any ApplicationTerminating
    private var hasRequestedTermination = false

    init(role: WindowRole, terminator: any ApplicationTerminating = NSApplicationTerminator()) {
        self.role = role
        self.terminator = terminator
    }

    var defaultContentSize: CGSize {
        switch role {
        case .authentication: CGSize(width: 760, height: 760)
        case .compact: CGSize(width: 400, height: 288)
        case .library: CGSize(width: 980, height: 700)
        }
    }

    var minimumContentSize: CGSize {
        switch role {
        case .authentication: CGSize(width: 760, height: 760)
        case .compact: CGSize(width: 400, height: 288)
        case .library: CGSize(width: 760, height: 540)
        }
    }

    var isResizable: Bool { role != .compact }
    var allowsFullScreen: Bool { role != .compact }
    var usesCompactChrome: Bool { role == .compact }

    var frameAutosaveName: String {
        switch role {
        case .authentication: ProductIdentity.FrameAutosaveName.authentication
        case .compact: ProductIdentity.FrameAutosaveName.compact
        case .library: ProductIdentity.FrameAutosaveName.library
        }
    }

    var legacyFrameAutosaveName: String {
        switch role {
        case .authentication: ProductIdentity.Legacy.authenticationFrameAutosaveName
        case .compact: ProductIdentity.Legacy.compactFrameAutosaveName
        case .library: ProductIdentity.Legacy.libraryFrameAutosaveName
        }
    }

    func windowLevel(alwaysOnTop: Bool) -> WindowLevel {
        role == .compact && alwaysOnTop ? .floating : .normal
    }

    func windowWillClose() {
        guard role != .library, !hasRequestedTermination else { return }
        hasRequestedTermination = true
        terminator.requestTermination()
    }
}

enum WindowFrameRestoration {
    static func frameToApply(savedFrame: CGRect, screens: [CGRect]) -> CGRect? {
        guard savedFrame.width > 0, savedFrame.height > 0,
              screens.contains(where: { $0.intersects(savedFrame) })
        else { return nil }
        return savedFrame
    }

    static func compactOriginToApply(savedFrame: CGRect, screens: [CGRect]) -> CGPoint? {
        guard let validFrame = frameToApply(savedFrame: savedFrame, screens: screens),
              screens.contains(where: { $0.contains(validFrame.origin) })
        else { return nil }
        return validFrame.origin
    }
}

enum WindowFrameMigration {
    static func migratedFrameString(
        currentValue: String?,
        legacyValue: String?,
        role: WindowRole,
        screens: [CGRect]
    ) -> String? {
        guard currentValue == nil, let legacyValue else { return nil }
        let legacyFrame = NSRectFromString(legacyValue)

        switch role {
        case .compact:
            guard let origin = WindowFrameRestoration.compactOriginToApply(
                savedFrame: legacyFrame,
                screens: screens
            ) else { return nil }
            return NSStringFromRect(NSRect(
                origin: origin,
                size: CGSize(width: 400, height: 288)
            ))
        case .authentication, .library:
            guard let validFrame = WindowFrameRestoration.frameToApply(
                savedFrame: legacyFrame,
                screens: screens
            ) else { return nil }
            return NSStringFromRect(validFrame)
        }
    }
}

/// A small, app-owned restoration payload. It deliberately stores only a
/// finite top-left origin; package data has no persistence or screen authority.
struct CompactWindowPositionRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let x: CGFloat
    let y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        schemaVersion = Self.schemaVersion
        self.x = x
        self.y = y
    }

    var isValid: Bool { schemaVersion == Self.schemaVersion && x.isFinite && y.isFinite }
}

struct CompactWindowPositionStore: Sendable {
    static let defaultKey = "Canis97.compact.window-position.v1"
    let key: String

    init(key: String = Self.defaultKey) { self.key = key }

    func load(from defaults: UserDefaults = .standard) -> CompactWindowPositionRecord? {
        guard let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(CompactWindowPositionRecord.self, from: data),
              record.isValid
        else { return nil }
        return record
    }

    func save(_ record: CompactWindowPositionRecord, to defaults: UserDefaults = .standard) {
        guard record.isValid, let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear(from defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

/// Pure geometry helpers make the compact bridge deterministic and testable
/// without creating an AppKit window or trusting package-supplied dimensions.
enum CompactWindowGeometry {
    static func frame(size: CGSize, preservingTopLeft topLeft: CGPoint) -> CGRect {
        CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    static func topLeft(of frame: CGRect) -> CGPoint { CGPoint(x: frame.minX, y: frame.maxY) }

    static func containingScreen(for topLeft: CGPoint, screens: [CGRect]) -> CGRect? {
        screens.first { $0.contains(topLeft) }
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        guard frame.width <= visibleFrame.width, frame.height <= visibleFrame.height else {
            return CGRect(origin: CGPoint(x: visibleFrame.midX - frame.width / 2, y: visibleFrame.midY - frame.height / 2), size: frame.size)
        }
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }
}

/// A role-scoped AppKit adapter. It never owns playback, app session state,
/// window delegates, or non-window preference data.
@MainActor
final class CompactWindowController {
    private let policy: WindowLifecyclePolicy
    private let restoresPersistedFrame: Bool
    private var closeObserver: NSObjectProtocol?
    private weak var attachedWindow: NSWindow?
    private let positionStore: CompactWindowPositionStore
    private let restoreNativeAppearance: @MainActor () -> Void
    private var hasRestoredCompactPosition = false

    init(
        role: WindowRole,
        terminator: any ApplicationTerminating = NSApplicationTerminator(),
        restoresPersistedFrame: Bool = true,
        positionStore: CompactWindowPositionStore = .init(),
        restoreNativeAppearance: @escaping @MainActor () -> Void = {}
    ) {
        policy = WindowLifecyclePolicy(role: role, terminator: terminator)
        self.restoresPersistedFrame = restoresPersistedFrame
        self.positionStore = positionStore
        self.restoreNativeAppearance = restoreNativeAppearance
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func attach(
        to window: NSWindow,
        alwaysOnTop: Bool,
        appearance: ValidatedSkinAppearance = .native
    ) {
        if attachedWindow !== window {
            removeCloseObserver()
            attachedWindow = window
            configure(window)
            installCloseObserver(for: window)
        }
        update(alwaysOnTop: alwaysOnTop)
        updateAppearance(appearance, in: window)
    }

    func update(alwaysOnTop: Bool) {
        guard let attachedWindow else { return }
        attachedWindow.level = switch policy.windowLevel(alwaysOnTop: alwaysOnTop) {
        case .normal: .normal
        case .floating: .floating
        }
    }

    /// Resolves only the already-validated finite appearance policy. No raw
    /// manifest value, style mask, or package persistence key reaches AppKit.
    func updateAppearance(_ appearance: ValidatedSkinAppearance, in window: NSWindow? = nil) {
        guard policy.role == .compact else { return }
        let window = window ?? attachedWindow
        guard let window else { return }
        let size = appearance.layoutPlan.presentationSize
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = size
        window.contentMaxSize = size
        if !applyCompactFrame(window, contentSize: size) {
            let nativeSize = CompactSkinSizeVariant.legacy400x288.contentSize
            window.contentMinSize = nativeSize
            window.contentMaxSize = nativeSize
            _ = applyCompactFrame(window, contentSize: nativeSize)
        }
    }

    @discardableResult
    private func applyCompactFrame(_ window: NSWindow, contentSize: CGSize) -> Bool {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard !visibleFrames.isEmpty else {
            window.setContentSize(contentSize)
            return true
        }
        var topLeft = CompactWindowGeometry.topLeft(of: window.frame)
        if !hasRestoredCompactPosition {
            hasRestoredCompactPosition = true
            let defaults = UserDefaults.standard
            if defaults.object(forKey: positionStore.key) != nil {
                guard let record = positionStore.load(from: defaults),
                      CompactWindowGeometry.containingScreen(for: CGPoint(x: record.x, y: record.y), screens: visibleFrames) != nil
                else {
                    positionStore.clear(from: defaults)
                    restoreNativeAppearance()
                    return false
                }
                topLeft = CGPoint(x: record.x, y: record.y)
            } else if !restoresPersistedFrame {
                center(window)
                topLeft = CompactWindowGeometry.topLeft(of: window.frame)
            }
        }
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let preferred = CompactWindowGeometry.frame(size: frameSize, preservingTopLeft: topLeft)
        let visible = CompactWindowGeometry.containingScreen(for: topLeft, screens: visibleFrames)
            ?? window.screen?.visibleFrame
            ?? visibleFrames[0]
        let clamped = CompactWindowGeometry.clamped(preferred, to: visible)
        window.setFrame(clamped, display: false)
        positionStore.save(.init(x: clamped.minX, y: clamped.maxY))
        return true
    }

    private func configure(_ window: NSWindow) {
        configureChrome(in: window)
        if restoresPersistedFrame {
            migrateLegacyFrameIfNeeded()
            window.setFrameAutosaveName(policy.frameAutosaveName)
        }
        window.contentMinSize = policy.minimumContentSize

        if policy.isResizable {
            window.styleMask.insert(.resizable)
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        } else {
            window.contentMaxSize = policy.defaultContentSize
            window.styleMask.remove(.resizable)
            window.styleMask.remove(.fullScreen)
        }
        if policy.allowsFullScreen {
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
        } else {
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
        }

        restoreFrameOrCenter(window)
    }

    /// The primary scene is also the authentication window, so its chrome must
    /// transition with the app state instead of being fixed at the Scene level.
    /// Compact playback remains closable through Command-W while removing the
    /// titled style that otherwise reserves visible title-bar geometry.
    private func configureChrome(in window: NSWindow) {
        if policy.usesCompactChrome {
            // A transparent borderless SwiftUI window may have no hit-testable
            // view under decorative pixels. Keep background mouse-down owned
            // by the window so it cannot fall through to another application.
            window.isMovable = true
            window.isMovableByWindowBackground = true
            window.styleMask.insert([.closable, .miniaturizable])
            window.styleMask.remove([.titled, .fullSizeContentView])
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .none
            setStandardWindowButtons(hidden: true, in: window)
        } else {
            window.isMovableByWindowBackground = false
            window.styleMask.insert([.titled, .closable, .miniaturizable])
            window.styleMask.remove(.fullSizeContentView)
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
            setStandardWindowButtons(hidden: false, in: window)
        }
    }

    private func setStandardWindowButtons(hidden: Bool, in window: NSWindow) {
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = hidden
        }
    }

    private func migrateLegacyFrameIfNeeded() {
        let currentKey = "NSWindow Frame \(policy.frameAutosaveName)"
        let legacyKey = "NSWindow Frame \(policy.legacyFrameAutosaveName)"
        let defaults = UserDefaults.standard
        guard let migrated = WindowFrameMigration.migratedFrameString(
            currentValue: defaults.string(forKey: currentKey),
            legacyValue: defaults.string(forKey: legacyKey),
            role: policy.role,
            screens: NSScreen.screens.map(\.visibleFrame)
        ) else { return }
        defaults.set(migrated, forKey: currentKey)
    }

    private func restoreFrameOrCenter(_ window: NSWindow) {
        let key = "NSWindow Frame \(policy.frameAutosaveName)"
        let savedFrame = restoresPersistedFrame
            ? UserDefaults.standard.string(forKey: key).map(NSRectFromString)
            : nil
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)

        if policy.role == .compact {
            if let savedFrame,
               let savedOrigin = WindowFrameRestoration.compactOriginToApply(
                   savedFrame: savedFrame,
                   screens: visibleFrames
               )
            {
                window.setFrameOrigin(savedOrigin)
                window.setContentSize(policy.defaultContentSize)
                window.setFrameOrigin(savedOrigin)
            } else {
                window.setContentSize(policy.defaultContentSize)
                center(window)
            }
            return
        }

        if let savedFrame,
           let validFrame = WindowFrameRestoration.frameToApply(savedFrame: savedFrame, screens: visibleFrames)
        {
            window.setFrame(validFrame, display: false)
            return
        }

        window.setContentSize(policy.defaultContentSize)
        center(window)
    }

    private func center(_ window: NSWindow) {
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        } else {
            window.center()
        }
    }

    private func installCloseObserver(for window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.policy.windowWillClose() }
        }
    }

    private func removeCloseObserver() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
    }
}

@MainActor
protocol WindowLifecycleAttaching {
    func attach(to window: NSWindow, alwaysOnTop: Bool)
}

extension CompactWindowController: WindowLifecycleAttaching {}

extension CompactWindowController {
    func attach(to window: NSWindow, alwaysOnTop: Bool) {
        attach(to: window, alwaysOnTop: alwaysOnTop, appearance: .native)
    }
}

struct WindowAttachmentView: NSViewRepresentable {
    let role: WindowRole
    let alwaysOnTop: Bool
    var appearance: ValidatedSkinAppearance = .native
    var restoresPersistedFrame = true
    var contentRegionAccessibilityIdentifier: String? = nil
    var restoreNativeAppearance: @MainActor () -> Void = {}

    func makeCoordinator() -> CompactWindowController {
        CompactWindowController(
            role: role,
            restoresPersistedFrame: restoresPersistedFrame,
            restoreNativeAppearance: restoreNativeAppearance
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if let contentRegionAccessibilityIdentifier {
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.group)
            view.setAccessibilityIdentifier(contentRegionAccessibilityIdentifier)
        }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window, alwaysOnTop: alwaysOnTop, appearance: appearance)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        context.coordinator.attach(to: window, alwaysOnTop: alwaysOnTop, appearance: appearance)
    }
}

@MainActor
final class ApplicationTerminationObserver {
    private var observer: NSObjectProtocol?

    init(shutdown: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            Task { @MainActor in shutdown() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
