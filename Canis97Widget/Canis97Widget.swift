import AppIntents
import SwiftUI
import WidgetKit

@main
struct Canis97WidgetBundle: WidgetBundle {
    var body: some Widget {
        Canis97NowPlayingWidget()
    }
}

struct Canis97NowPlayingWidget: Widget {
    let kind = NativeReachConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Canis97TimelineProvider()) { entry in
            Canis97WidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Canis97WidgetBackdrop()
                }
        }
        .configurationDisplayName("Canis97 Now Playing")
        .description("Shows the last semantic channel and program published by Canis97.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Canis97WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NativeReachSnapshot?
}

struct Canis97TimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> Canis97WidgetEntry {
        Canis97WidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Canis97WidgetEntry) -> Void) {
        completion(Canis97WidgetEntry(date: .now, snapshot: loadSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Canis97WidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot()
        let entry = Canis97WidgetEntry(date: now, snapshot: snapshot)
        let refreshAt = snapshot?.nextWidgetRefresh(after: now)
            ?? now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshAt)))
    }

    private func loadSnapshot() -> NativeReachSnapshot? {
        guard let defaults = UserDefaults(suiteName: NativeReachConstants.appGroupIdentifier),
              let data = defaults.data(forKey: NativeReachConstants.cacheKey)
        else { return nil }
        return NativeReachSnapshot.decoded(from: data)
    }
}

private struct Canis97WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Canis97WidgetEntry
    private let familyOverride: WidgetFamily?

    init(entry: Canis97WidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        if let snapshot = entry.snapshot {
            Group {
                if (familyOverride ?? family) == .systemMedium {
                    mediumLayout(snapshot)
                } else {
                    smallLayout(snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(NativeReachRoute.library.url)
        } else {
            Link(destination: NativeReachRoute.library.url!) {
                VStack(alignment: .leading, spacing: 10) {
                    widgetBrand
                    Spacer(minLength: 0)
                    Text("Open Canis97")
                        .font(.title3.weight(.bold))
                    Text("Sign in to put your stations here.")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func smallLayout(_ snapshot: NativeReachSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                compactWidgetBrand
                Spacer(minLength: 4)
                if snapshot.currentChannel != nil, snapshot.playback != .unavailable {
                    playPauseControl(snapshot, compact: true)
                } else {
                    statusBadge(snapshot)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 3) {
                if let channel = snapshot.currentChannel {
                    channelEyebrow(channel)
                }
                Text(primaryCopy(snapshot))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(smallSecondaryCopy(snapshot))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                if snapshot.currentChannel == nil, !snapshot.favorites.isEmpty {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(WidgetPalette.accent)
                    Text("\(snapshot.favorites.count) favorites")
                        .lineLimit(1)
                } else if let channel = snapshot.currentChannel {
                    Text(channel.name)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                freshness(snapshot)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetPalette.subtle)
        }
    }

    private func mediumLayout(_ snapshot: NativeReachSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                widgetBrand
                Spacer(minLength: 8)
                freshness(snapshot)
                transportControls(snapshot)
            }

            HStack(alignment: .center, spacing: 12) {
                channelTile(snapshot.currentChannel)

                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryCopy(snapshot))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(secondaryCopy(snapshot))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetPalette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            favorites(snapshot)
        }
    }

    private var widgetBrand: some View {
        HStack(spacing: 6) {
            SignalMark()
                .frame(width: 18, height: 18)
            Text("CANIS")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.4)
            Text("97")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(WidgetPalette.accent)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canis97")
    }

    private var compactWidgetBrand: some View {
        HStack(spacing: 5) {
            SignalMark()
                .frame(width: 18, height: 18)
            HStack(spacing: 1) {
                Text("C")
                Text("97")
                    .foregroundStyle(WidgetPalette.accent)
            }
            .font(.system(size: 10, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canis97")
    }

    private func channelTile(_ channel: NativeReachChannel?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }

            if let number = channel?.displayNumber {
                VStack(spacing: -2) {
                    Text("CH")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(WidgetPalette.muted)
                    Text(number, format: .number.grouping(.never))
                        .font(.system(size: number > 999 ? 24 : 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }
            } else {
                SignalMark()
                    .frame(width: 40, height: 40)
            }
        }
        .frame(width: 68, height: 62)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(WidgetPalette.accent)
                .frame(width: 24, height: 3)
                .offset(y: 1)
        }
        .accessibilityHidden(true)
    }

    private func channelEyebrow(_ channel: NativeReachChannel) -> some View {
        HStack(spacing: 4) {
            if let number = channel.displayNumber {
                Text("CH \(number)")
            }
            if let category = channel.category {
                Text(category.uppercased())
                    .lineLimit(1)
            }
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(WidgetPalette.accent)
    }

    private func statusBadge(_ snapshot: NativeReachSnapshot) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(snapshot))
                .frame(width: 5, height: 5)
            Text(statusCopy(snapshot))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(statusColor(snapshot))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07), in: Capsule())
        .accessibilityLabel(statusAccessibilityLabel(snapshot))
    }

    private func primaryCopy(_ snapshot: NativeReachSnapshot) -> String {
        snapshot.currentProgram?.title
            ?? snapshot.currentChannel?.name
            ?? "Ready when you are"
    }

    private func secondaryCopy(_ snapshot: NativeReachSnapshot) -> String {
        if let program = snapshot.currentProgram {
            return program.artist ?? snapshot.currentChannel?.name ?? "Live program"
        }
        if let channel = snapshot.currentChannel {
            return channel.category ?? "Live channel"
        }
        return snapshot.favorites.isEmpty
            ? "Open Canis97 to choose a channel"
            : "Choose a favorite below"
    }

    private func smallSecondaryCopy(_ snapshot: NativeReachSnapshot) -> String {
        guard snapshot.currentChannel == nil else { return secondaryCopy(snapshot) }
        return "Tap to choose a station"
    }

    private func statusCopy(_ snapshot: NativeReachSnapshot) -> String {
        switch snapshot.playback {
        case .playing: "LIVE"
        case .paused: "PAUSED"
        case .stopped: "READY"
        case .unavailable: "OFFLINE"
        }
    }

    private func statusColor(_ snapshot: NativeReachSnapshot) -> Color {
        switch snapshot.playback {
        case .playing: WidgetPalette.accent
        case .paused, .stopped: WidgetPalette.muted
        case .unavailable: WidgetPalette.warning
        }
    }

    private func statusAccessibilityLabel(_ snapshot: NativeReachSnapshot) -> String {
        switch snapshot.playback {
        case .playing: "Playing live"
        case .paused: "Playback paused"
        case .stopped: "Ready to listen"
        case .unavailable: "Playback unavailable"
        }
    }

    private func transportControls(_ snapshot: NativeReachSnapshot) -> some View {
        let enabled = snapshot.currentChannel != nil && snapshot.playback != .unavailable
        return HStack(spacing: 5) {
            widgetControl(
                route: .previousChannel,
                symbol: "backward.end.fill",
                label: "Previous channel",
                enabled: enabled
            )
            playPauseControl(snapshot, compact: false)
                .disabled(!enabled)
            widgetControl(
                route: .nextChannel,
                symbol: "forward.end.fill",
                label: "Next channel",
                enabled: enabled
            )
        }
    }

    private func playPauseControl(_ snapshot: NativeReachSnapshot, compact: Bool) -> some View {
        let isPlaying = snapshot.playback == .playing
        return Button(intent: OpenURLIntent(NativeReachRoute.togglePlayback.url!)) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 10 : 9, weight: .black))
                .foregroundStyle(WidgetPalette.ink)
                .frame(width: compact ? 28 : 26, height: compact ? 28 : 26)
                .background(WidgetPalette.accent, in: Circle())
                .shadow(color: WidgetPalette.accent.opacity(0.2), radius: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause Canis97" : "Play Canis97")
    }

    private func widgetControl(
        route: NativeReachRoute,
        symbol: String,
        label: String,
        enabled: Bool
    ) -> some View {
        Button(intent: OpenURLIntent(route.url!)) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.88 : 0.3))
                .frame(width: 26, height: 26)
                .background(.white.opacity(enabled ? 0.08 : 0.035), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(enabled ? 0.08 : 0.03), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func favorites(_ snapshot: NativeReachSnapshot) -> some View {
        if snapshot.favorites.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                Text("Open Canis97 to choose a station")
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetPalette.subtle)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                ForEach(snapshot.favorites.prefix(3)) { channel in
                    if let url = NativeReachRoute.tune(channelID: channel.id).url {
                        Link(destination: url) {
                            HStack(spacing: 5) {
                                if let number = channel.displayNumber {
                                    Text(number, format: .number.grouping(.never))
                                        .foregroundStyle(WidgetPalette.accent)
                                }
                                Text(channel.name)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                            }
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                            .background(
                                .white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func freshness(_ snapshot: NativeReachSnapshot) -> some View {
        let freshness = snapshot.freshness(at: entry.date)
        let copy: Text = switch freshness {
        case .current: Text(snapshot.updatedAt, format: .dateTime.hour().minute())
        case .stale: Text("STALE · \(snapshot.updatedAt, format: .dateTime.hour().minute())")
        case .unavailable: Text("UPDATE UNKNOWN")
        }
        return copy
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(freshness == .current ? WidgetPalette.subtle : WidgetPalette.warning)
            .lineLimit(1)
    }
}

private struct SignalMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
            Circle()
                .stroke(WidgetPalette.accent.opacity(0.45), lineWidth: 1)
                .padding(4)
            Circle()
                .fill(WidgetPalette.accent)
                .padding(7)
                .shadow(color: WidgetPalette.accent.opacity(0.75), radius: 4)
        }
    }
}

private struct Canis97WidgetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WidgetPalette.ink, WidgetPalette.deepGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(WidgetPalette.accent.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 30)
                .offset(x: 110, y: -90)
            LinearGradient(
                colors: [.white.opacity(0.045), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}

private enum WidgetPalette {
    static let ink = Color(red: 7 / 255, green: 10 / 255, blue: 13 / 255)
    static let deepGreen = Color(red: 13 / 255, green: 25 / 255, blue: 22 / 255)
    static let accent = Color(red: 198 / 255, green: 255 / 255, blue: 0 / 255)
    static let muted = Color.white.opacity(0.62)
    static let subtle = Color.white.opacity(0.42)
    static let warning = Color(red: 1, green: 0.67, blue: 0.24)
}

private extension NativeReachSnapshot {
    static var placeholder: Self {
        Self(
            updatedAt: .now,
            playback: .playing,
            currentChannel: NativeReachChannel(
                id: "placeholder",
                name: "Orbit",
                displayNumber: 8,
                category: "Music",
                isFavorite: true
            ),
            currentProgram: NativeReachProgram(
                title: "A Little More Light",
                artist: "The Satellites",
                startedAt: .now
            ),
            metadataObservedAt: .now,
            favorites: [
                NativeReachChannel(
                    id: "favorite-1",
                    name: "SiriusXMU",
                    displayNumber: 35,
                    category: "Music",
                    isFavorite: true
                ),
                NativeReachChannel(
                    id: "favorite-2",
                    name: "The Spectrum",
                    displayNumber: 28,
                    category: "Music",
                    isFavorite: true
                ),
                NativeReachChannel(
                    id: "favorite-3",
                    name: "Alt Nation",
                    displayNumber: 36,
                    category: "Music",
                    isFavorite: true
                ),
            ].compactMap { $0 }
        )
    }
}
