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
        case .authentication: CGSize(width: 760, height: 620)
        case .compact: CGSize(width: 400, height: 288)
        case .library: CGSize(width: 980, height: 700)
        }
    }

    var minimumContentSize: CGSize {
        switch role {
        case .authentication: CGSize(width: 760, height: 620)
        case .compact: CGSize(width: 400, height: 288)
        case .library: CGSize(width: 760, height: 540)
        }
    }

    var isResizable: Bool { role != .compact }
    var allowsFullScreen: Bool { role != .compact }

    var frameAutosaveName: String {
        switch role {
        case .authentication: "SiriusMac.authentication.frame"
        case .compact: "SiriusMac.compact.frame"
        case .library: "SiriusMac.library.frame"
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

/// A role-scoped AppKit adapter. It never owns playback, app session state,
/// window delegates, or non-window preference data.
@MainActor
final class CompactWindowController {
    private let policy: WindowLifecyclePolicy
    private let restoresPersistedFrame: Bool
    private var closeObserver: NSObjectProtocol?
    private weak var attachedWindow: NSWindow?

    init(
        role: WindowRole,
        terminator: any ApplicationTerminating = NSApplicationTerminator(),
        restoresPersistedFrame: Bool = true
    ) {
        policy = WindowLifecyclePolicy(role: role, terminator: terminator)
        self.restoresPersistedFrame = restoresPersistedFrame
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func attach(to window: NSWindow, alwaysOnTop: Bool) {
        if attachedWindow !== window {
            removeCloseObserver()
            attachedWindow = window
            configure(window)
            installCloseObserver(for: window)
        }
        update(alwaysOnTop: alwaysOnTop)
    }

    func update(alwaysOnTop: Bool) {
        guard let attachedWindow else { return }
        attachedWindow.level = switch policy.windowLevel(alwaysOnTop: alwaysOnTop) {
        case .normal: .normal
        case .floating: .floating
        }
    }

    private func configure(_ window: NSWindow) {
        if restoresPersistedFrame {
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

struct WindowAttachmentView: NSViewRepresentable {
    let role: WindowRole
    let alwaysOnTop: Bool
    var restoresPersistedFrame = true
    var contentRegionAccessibilityIdentifier: String? = nil

    func makeCoordinator() -> CompactWindowController {
        CompactWindowController(role: role, restoresPersistedFrame: restoresPersistedFrame)
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
            context.coordinator.attach(to: window, alwaysOnTop: alwaysOnTop)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        context.coordinator.attach(to: window, alwaysOnTop: alwaysOnTop)
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
