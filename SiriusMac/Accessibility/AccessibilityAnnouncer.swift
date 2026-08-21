import AppKit

/// An injected boundary for the one native assistive-technology side effect.
/// Tests use a spy; production is the only implementation that reaches AppKit.
@MainActor
protocol AccessibilityAnnouncementPosting: AnyObject {
    func postAnnouncement(_ message: String)
}

@MainActor
final class SystemAccessibilityAnnouncementPoster: AccessibilityAnnouncementPosting {
    func postAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApp,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

/// The only state changes Sirius Mac may announce. Cases intentionally carry
/// no provider content, error text, credentials, URLs, renderer strings, or
/// transport values.
enum AccessibilityAnnouncementEvent: Hashable {
    case tuned(generation: Int)
    case playing(generation: Int)
    case paused(generation: Int)
    case favoriteAdded(generation: Int)
    case favoriteRemoved(generation: Int)
    case playbackFailed(generation: Int)
    case metadataStale(generation: Int)
    case metadataUnavailable(generation: Int)

    var message: String {
        switch self {
        case .tuned: "Tuned to selected channel"
        case .playing: "Playing"
        case .paused: "Paused"
        case .favoriteAdded: "Added to Favorites"
        case .favoriteRemoved: "Removed from Favorites"
        case .playbackFailed: "Playback unavailable"
        case .metadataStale: "Current program is stale"
        case .metadataUnavailable: "Current program unavailable"
        }
    }
}

/// Deduplicates closed semantic events for the active session lifetime. It
/// cannot accept arbitrary strings, which keeps the VoiceOver boundary safe.
@MainActor
final class AccessibilityAnnouncer {
    private let poster: any AccessibilityAnnouncementPosting
    private var announcedEvents = Set<AccessibilityAnnouncementEvent>()
    private var isShutdown = false

    init(poster: any AccessibilityAnnouncementPosting = SystemAccessibilityAnnouncementPoster()) {
        self.poster = poster
    }

    func announce(_ event: AccessibilityAnnouncementEvent) {
        guard !isShutdown, announcedEvents.insert(event).inserted else { return }
        poster.postAnnouncement(event.message)
    }

    func shutdown() {
        isShutdown = true
        announcedEvents.removeAll()
    }
}
