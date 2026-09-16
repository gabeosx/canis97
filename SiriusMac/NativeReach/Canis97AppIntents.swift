import AppIntents
import Foundation

struct Canis97ChannelEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Canis97 Channel")
    static let defaultQuery = Canis97ChannelQuery()

    let id: String
    let name: String
    let displayNumber: Int?
    let category: String?
    let isFavorite: Bool

    init(_ channel: NativeReachChannel) {
        id = channel.id
        name = channel.name
        displayNumber = channel.displayNumber
        category = channel.category
        isFavorite = channel.isFavorite
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = [displayNumber.map { "Channel \($0)" }, category, isFavorite ? "Favorite" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }
}

struct Canis97ChannelQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [Canis97ChannelEntity] {
        let wanted = Set(identifiers)
        return NativeReachRuntime.shared.channelEntities()
            .filter { wanted.contains($0.id) }
            .map(Canis97ChannelEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [Canis97ChannelEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return NativeReachRuntime.shared.channelEntities()
            .filter { channel in
                needle.isEmpty || [channel.name, channel.category, channel.displayNumber.map(String.init)]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
            }
            .map(Canis97ChannelEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [Canis97ChannelEntity] {
        NativeReachRuntime.shared.channelEntities()
            .sorted { left, right in
                if left.isFavorite != right.isFavorite { return left.isFavorite }
                return (left.displayNumber ?? .max) < (right.displayNumber ?? .max)
            }
            .prefix(40)
            .map(Canis97ChannelEntity.init)
    }
}

struct TuneCanis97ChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Tune Canis97 Channel"
    static let description = IntentDescription("Tunes one entitled live channel through the current Canis97 session.")
    static let openAppWhenRun = true

    @Parameter(title: "Channel") var channel: Canis97ChannelEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.tune(channelID: channel.id)))
    }
}

struct ToggleCanis97PlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause Canis97"
    static let description = IntentDescription("Plays or pauses the confirmed Canis97 live channel.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.togglePlayback()))
    }
}

struct StopCanis97PlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Canis97"
    static let description = IntentDescription("Stops live playback and cancels a pending tune.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.stopPlayback()))
    }
}

struct PreviousCanis97ChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Canis97 Channel"
    static let description = IntentDescription("Tunes the previous available channel in the active Canis97 queue.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.previousChannel()))
    }
}

struct NextCanis97ChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Canis97 Channel"
    static let description = IntentDescription("Tunes the next available channel in the active Canis97 queue.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.nextChannel()))
    }
}

struct OpenCanis97LibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Canis97 Library"
    static let description = IntentDescription("Opens the Canis97 channel library.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.handle(.library)))
    }
}

struct WhatIsPlayingOnCanis97Intent: AppIntent {
    static let title: LocalizedStringResource = "What's Playing on Canis97"
    static let description = IntentDescription("Reports the confirmed current channel and fresh semantic program metadata.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await .result(dialog: NativeReachIntentCopy.dialog(for: NativeReachRuntime.shared.whatIsPlaying()))
    }
}

struct Canis97Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TuneCanis97ChannelIntent(),
            phrases: ["Tune \(\.$channel) in \(.applicationName)"],
            shortTitle: "Tune Channel",
            systemImageName: "radio"
        )
        AppShortcut(
            intent: ToggleCanis97PlaybackIntent(),
            phrases: ["Play or pause \(.applicationName)"],
            shortTitle: "Play or Pause",
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: StopCanis97PlaybackIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: PreviousCanis97ChannelIntent(),
            phrases: ["Previous channel in \(.applicationName)"],
            shortTitle: "Previous Channel",
            systemImageName: "backward.end.fill"
        )
        AppShortcut(
            intent: NextCanis97ChannelIntent(),
            phrases: ["Next channel in \(.applicationName)"],
            shortTitle: "Next Channel",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: OpenCanis97LibraryIntent(),
            phrases: ["Open \(.applicationName) Library"],
            shortTitle: "Open Library",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: WhatIsPlayingOnCanis97Intent(),
            phrases: ["What's playing on \(.applicationName)"],
            shortTitle: "What's Playing",
            systemImageName: "waveform"
        )
    }
}

private enum NativeReachIntentCopy {
    static func dialog(for outcome: NativeReachActionOutcome) -> IntentDialog {
        switch outcome {
        case let .accepted(message): IntentDialog(stringLiteral: message)
        case .authenticationRequired: "Sign in to Canis97 first."
        case .catalogUnavailable: "Open Canis97 and refresh your channels first."
        case .channelUnavailable: "That channel is no longer available in the current lineup."
        case .commandUnavailable: "That action is not available in the current Canis97 state."
        }
    }
}
