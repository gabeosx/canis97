import AppKit
import SwiftUI

struct CompactPlayerView: View {
    let presentation: CompactPlayerPresentation
    let appearance: ValidatedSkinAppearance
    let onAction: @MainActor (CompactPlayerAction) -> Void
    let isAlwaysOnTop: Bool
    let onAlwaysOnTopChanged: @MainActor (Bool) -> Void
    let onAppearanceRecovery: @MainActor () -> Void
    @State private var showsNativeAppearanceRecoveryStatus = false

    private var renderingAppearance: ValidatedSkinAppearance {
        appearance.renderableAppearance { NSImage(contentsOf: $0) != nil }
    }
    private var style: CompactSkinStyle { renderingAppearance.style }
    private var needsNativeAppearanceRecovery: Bool {
        appearance.reference != .native && renderingAppearance.reference == .native
    }

    init(
        presentation: CompactPlayerPresentation,
        appearance: ValidatedSkinAppearance = .native,
        onAction: @escaping @MainActor (CompactPlayerAction) -> Void,
        isAlwaysOnTop: Bool = false,
        onAlwaysOnTopChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onAppearanceRecovery: @escaping @MainActor () -> Void = {}
    ) {
        self.presentation = presentation
        self.appearance = appearance
        self.onAction = onAction
        self.isAlwaysOnTop = isAlwaysOnTop
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onAppearanceRecovery = onAppearanceRecovery
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            decorativeImage(at: renderingAppearance.backgroundAssetURL)
            VStack(alignment: .leading, spacing: style.sectionSpacing) {
                if let channel = presentation.channelIdentity {
                    populatedContent(channel)
                } else {
                    emptyContent
                }
            }
            .padding(style.padding)
        }
        .frame(width: style.contentSize.width, height: style.contentSize.height, alignment: .topLeading)
        .background(surfaceBackground(.canvas))
        .tint(surfaceTint(.interactiveAccent))
        .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius))
        .environment(\.colorScheme, contentColorScheme)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sirius Mac compact player")
        .accessibilityIdentifier("compact.canvas")
        .onChange(of: needsNativeAppearanceRecovery, initial: true) { _, needsRecovery in
            guard needsRecovery else { return }
            showsNativeAppearanceRecoveryStatus = true
            onAppearanceRecovery()
        }
        .onChange(of: appearance.reference) { _, reference in
            guard reference != .native, !needsNativeAppearanceRecovery else { return }
            showsNativeAppearanceRecoveryStatus = false
        }
    }

    private var contentColorScheme: ColorScheme {
        switch style.foregroundColorScheme {
        case .light: .light
        case .dark: .dark
        }
    }

    @ViewBuilder
    private func populatedContent(_ channel: CompactPlayerPresentation.ChannelIdentity) -> some View {
        ZStack {
            decorativeImage(at: renderingAppearance.metadataPanelAssetURL)
            HStack(alignment: .top, spacing: 8) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(channel.displayText)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)
                            .help(channel.displayText)
                            .accessibilityLabel("Channel \(channel.displayText)")
                        Spacer(minLength: 4)
                        Button(action: { onAction(.toggleFavorite) }) {
                            Image(systemName: presentation.isFavorite ? "star.fill" : "star")
                                .frame(width: 28, height: 28)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(presentation.isFavorite ? Color(hex: style.accentHex) : .secondary)
                        .help(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityIdentifier("compact.favorite")
                        .accessibilityLabel(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityValue(presentation.isFavorite ? "Favorite" : "Not favorite")
                        .accessibilitySortPriority(40)
                    }
                    metadata
                }
            }
            .padding(4)
        }
        .background(surfaceBackground(.metadata))
        .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius))
        statusAndRecovery
        transport
        footer
    }

    private var artwork: some View {
        Group {
            switch presentation.artwork {
            case let .data(artwork):
                NativeArtworkImage(artwork: artwork)
            case .placeholder, .none:
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .background(surfaceBackground(.metadata))
        .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius))
        .accessibilityLabel(presentation.primaryMetadata.map { "Artwork for \($0)" } ?? presentation.channelIdentity.map { "Artwork for channel \($0.displayText)" } ?? "Artwork")
        .accessibilitySortPriority(60)
    }

    @ViewBuilder
    private var metadata: some View {
        if let primary = presentation.primaryMetadata {
            Text(primary)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(CompactPlayerPresentation.metadataLineLimit)
                .help(primary)
                .accessibilityLabel("Current program: \(primary)")
                .accessibilityValue(primary)
                .accessibilitySortPriority(55)
        }
        if let secondary = presentation.secondaryMetadata {
            Text(secondary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(CompactPlayerPresentation.metadataLineLimit)
                .help(secondary)
                .accessibilityLabel("Artist: \(secondary)")
                .accessibilityValue(secondary)
                .accessibilitySortPriority(54)
        }
    }

    @ViewBuilder
    private var statusAndRecovery: some View {
        if let status = presentation.status {
            let surface = statusSurface(for: status)
            HStack(spacing: 4) {
                switch status {
                case .pending:
                    ProgressView().controlSize(.small)
                    Text("Loading playback")
                case .playing:
                    Label("Playing", systemImage: "play.fill")
                case .paused:
                    Label("Paused", systemImage: "pause.fill")
                case .stopped:
                    Label("Stopped", systemImage: "stop.fill")
                case let .unavailable(recovery):
                    Text("Playback couldn’t start.")
                    Button(recovery.title) { onAction(recovery.compactAction) }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceBackground(surface))
            .tint(surfaceTint(surface))
            .accessibilityValue(status.accessibilityValue)
            .accessibilityIdentifier("compact.status")
            .accessibilitySortPriority(50)
        }
        if needsNativeAppearanceRecovery || showsNativeAppearanceRecoveryStatus {
            Text("Native appearance restored because the selected decoration is unavailable.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(surfaceBackground(.criticalState))
                .tint(surfaceTint(.criticalState))
                .accessibilityIdentifier("compact.appearance-recovery")
                .accessibilitySortPriority(45)
        }
    }

    @ViewBuilder
    private var transport: some View {
        if let transport = presentation.transport {
            HStack(spacing: 8) {
                transportButton("Previous", systemImage: "backward.fill", enabled: transport.previousEnabled, action: .previous)
                transportButton(transport.playPause == .pause ? "Pause" : "Play Live", systemImage: transport.playPause == .pause ? "pause.fill" : "play.fill", enabled: true, action: .playPause)
                transportButton("Next", systemImage: "forward.fill", enabled: transport.nextEnabled, action: .next)
            }
            .frame(maxWidth: .infinity)
            .padding(4)
            .background(surfaceBackground(.transport))
            .tint(surfaceTint(.interactiveAccent))
        }
    }

    private func transportButton(_ title: String, systemImage: String, enabled: Bool, action: CompactPlayerAction) -> some View {
        Button(action: { onAction(action) }) {
            Image(systemName: systemImage)
                .frame(width: CompactPlayerPresentation.transportControlSize, height: CompactPlayerPresentation.transportControlSize)
        }
        .disabled(!enabled)
        .help(title)
        .accessibilityIdentifier("compact.transport.\(accessibilityIdentifier(for: action))")
        .accessibilityLabel(title)
        .accessibilityValue(enabled ? "Available" : "Unavailable for the current queue")
        .accessibilityHint(enabled ? "" : "Unavailable for the current queue")
        .accessibilitySortPriority(30)
    }

    private var footer: some View {
        HStack {
            Button { onAction(.showLibrary) } label: {
                Label("Show Library", systemImage: "rectangle.stack")
            }
                .help("Show Library")
                .accessibilityIdentifier("compact.show-library")
                .accessibilityLabel("Show Library")
                .accessibilitySortPriority(20)
            Spacer()
            Menu {
                Toggle(
                    "Always on Top",
                    isOn: Binding(
                        get: { isAlwaysOnTop },
                        set: { onAlwaysOnTopChanged($0) }
                    )
                )
                .accessibilityIdentifier("compact.always-on-top")
                .accessibilityLabel("Always on Top")
                .accessibilityValue(isAlwaysOnTop ? "On" : "Off")
                .accessibilitySortPriority(10)
                Divider()
                Button("Sign Out") { onAction(.signOut) }
                    .accessibilityIdentifier("compact.sign-out")
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .font(.system(size: 12))
        .padding(4)
        .background(surfaceBackground(.footer))
        .tint(surfaceTint(.interactiveAccent))
    }

    private func accessibilityIdentifier(for action: CompactPlayerAction) -> String {
        switch action {
        case .previous: "previous"
        case .playPause: "play-pause"
        case .next: "next"
        case .toggleFavorite: "favorite"
        case .showLibrary: "show-library"
        case .toggleAlwaysOnTop: "always-on-top"
        case .retryPlayback: "retry"
        case .signInAgain: "sign-in-again"
        case .refreshLibrary: "refresh-library"
        case .signOut: "sign-out"
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(presentation.emptyTitle ?? "Nothing Playing").font(.system(size: 24, weight: .semibold))
            statusAndRecovery
            Button(presentation.emptyLibraryButtonTitle ?? "Open Library") { onAction(.showLibrary) }
                .accessibilityIdentifier("compact.show-library")
                .accessibilityLabel("Open Library")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func statusSurface(for status: CompactPlayerPresentation.Status) -> CompactSkinSurface {
        switch status {
        case .unavailable:
            .criticalState
        case .pending, .playing, .paused, .stopped:
            .status
        }
    }

    private func surfaceBackground(_ surface: CompactSkinSurface) -> some View {
        let treatment = renderingAppearance.surfaceTreatment(for: surface)
        return RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
            .fill(Color(hex: treatment.fillHex).opacity(treatment.fillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                    .stroke(
                        Color(hex: treatment.strokeHex).opacity(treatment.strokeOpacity),
                        lineWidth: 1
                    )
            }
    }

    private func surfaceTint(_ surface: CompactSkinSurface) -> Color {
        Color(hex: renderingAppearance.surfaceTreatment(for: surface).tintHex)
    }

    @ViewBuilder
    private func decorativeImage(at url: URL?) -> some View {
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private extension CompactRecoveryAction {
    var compactAction: CompactPlayerAction {
        switch self {
        case .tryAgain: .retryPlayback
        case .signInAgain: .signInAgain
        case .refreshLibrary: .refreshLibrary
        }
    }
}

private extension CompactPlayerPresentation.Status {
    var accessibilityValue: String {
        switch self {
        case .pending: "Playback pending"
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unavailable: "Playback unavailable"
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

#Preview("Playing") {
    CompactPlayerView(
        presentation: .confirmed(channel: .init(number: 42, name: "The Spectrum"), artwork: .placeholder, primaryMetadata: "An unusually long Unicode title — 音楽と星空のためのライブ・ラジオ・セッション", secondaryMetadata: "An unusually long artist name — कलाकार और अतिथि", playback: .playing, isFavorite: true, queueAvailability: .both),
        onAction: { _ in }
    )
}

#Preview("Nothing Playing") {
    CompactPlayerView(presentation: .empty(), onAction: { _ in })
}

#Preview("Loading") {
    CompactPlayerView(presentation: .empty(status: .pending), onAction: { _ in })
}

#Preview("Paused") {
    CompactPlayerView(
        presentation: .confirmed(channel: .init(number: 7, name: "Fallback Channel"), artwork: .placeholder, primaryMetadata: "Current program unavailable", secondaryMetadata: "7 · Fallback Channel", playback: .paused, isFavorite: false, queueAvailability: .none),
        onAction: { _ in }
    )
}

#Preview("Playback Error") {
    CompactPlayerView(presentation: .empty(status: .unavailable(.tryAgain)), onAction: { _ in })
}
