import AppKit
import SwiftUI

struct CompactPlayerView: View {
    let presentation: CompactPlayerPresentation
    let appearance: ValidatedSkinAppearance
    let onAction: @MainActor (CompactPlayerAction) -> Void
    let isAlwaysOnTop: Bool
    let onAlwaysOnTopChanged: @MainActor (Bool) -> Void
    let onAppearanceRecovery: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            appOwnedDecorativeSurfaces
            if renderingAppearance.layoutPlan.isLegacy {
                VStack(alignment: .leading, spacing: style.sectionSpacing) {
                    if let channel = presentation.channelIdentity {
                        populatedContent(channel)
                    } else {
                        emptyContent
                    }
                }
                .padding(style.padding)
            } else {
                expressiveContent
            }
        }
        .frame(width: style.contentSize.width, height: style.contentSize.height, alignment: .topLeading)
        .background(surfaceBackground(.canvas))
        .tint(surfaceTint(.interactiveAccent))
        .clipShape(CompactSkinSilhouetteShape(variant: renderingAppearance.layoutPlan.silhouette, cornerRadius: renderingAppearance.cornerRadius))
        .environment(\.colorScheme, contentColorScheme)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ProductIdentity.displayName) compact player")
        .accessibilityIdentifier("compact.canvas")
        .id(renderingAppearance.reference)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: renderingAppearance.reference)
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

    /// The semantic registry is fixed in this source order. Schema-v3 supplies
    /// only prevalidated frames; it never creates a control or carries action,
    /// help, accessibility, keyboard, or playback authority.
    private var expressiveContent: some View {
        let plan = renderingAppearance.layoutPlan
        return ZStack(alignment: .topLeading) {
            expressiveMaterialLayer
            expressiveSlot(.artwork) { artwork }
            expressiveSlot(.channelIdentity) {
                let channelText = presentation.channelIdentity?.displayText ?? "Nothing Playing"
                Text(channelText)
                    .font(skinFont(plan.typography.display, size: 18, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(channelText)
                    .accessibilityLabel("Channel \(channelText)")
                    .accessibilityValue(channelText)
            }
            expressiveSlot(.metadata) { metadata }
            expressiveSlot(.favorite) { favoriteButton }
            expressiveSlot(.status) { statusAndRecovery }
            expressiveSlot(.transport) { transport }
            expressiveSlot(.library) { libraryButton }
            expressiveSlot(.overflowMenu) { overflowMenu }
        }
        .overlay(alignment: .topLeading) {
            ForEach(Array(plan.dragRegions.enumerated()), id: \.offset) { _, drag in
                Color.clear
                    .contentShape(.rect)
                    .frame(width: CGFloat(drag.width), height: CGFloat(drag.height))
                    .offset(x: CGFloat(drag.x), y: CGFloat(drag.y))
                    .gesture(WindowDragGesture())
                    .allowsHitTesting(true)
                    .accessibilityHidden(true)
            }
        }
    }

    private func expressiveSlot<Content: View>(
        _ slot: CompactSkinSemanticSlot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        guard let frame = renderingAppearance.layoutPlan.slotFrames[slot] else { return AnyView(EmptyView()) }
        return AnyView(
            content()
                .frame(width: CGFloat(frame.width), height: CGFloat(frame.height), alignment: .topLeading)
                .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
        )
    }

    private func skinFont(_ token: CompactSkinTypographyToken, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch token {
        case .systemDefault: .system(size: size, weight: weight)
        case .systemRounded: .system(size: size, weight: weight, design: .rounded)
        case .systemMonospaced: .system(size: size, weight: weight, design: .monospaced)
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
                            .font(.system(size: 18, weight: .bold, design: .rounded))
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
        .padding(CompactPlayerPresentation.focusClearance)
    }

    private var favoriteButton: some View {
        Button(action: { onAction(.toggleFavorite) }) {
            Image(systemName: presentation.isFavorite ? "star.fill" : "star")
                .frame(width: CompactPlayerPresentation.transportControlSize, height: CompactPlayerPresentation.transportControlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(presentation.isFavorite ? Color(hex: style.accentHex) : .secondary)
        .help(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityIdentifier("compact.favorite")
        .accessibilityLabel(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityValue(presentation.isFavorite ? "Favorite" : "Not favorite")
        .accessibilitySortPriority(40)
        .padding(CompactPlayerPresentation.focusClearance)
        .disabled(presentation.channelIdentity == nil)
    }

    @ViewBuilder
    private var metadata: some View {
        if let primary = presentation.primaryMetadata {
            Text(primary)
                .font(skinFont(renderingAppearance.layoutPlan.typography.body, size: 14, weight: .semibold))
                .lineLimit(CompactPlayerPresentation.metadataLineLimit)
                .truncationMode(.tail)
                .help(primary)
                .accessibilityLabel("Current program: \(primary)")
                .accessibilityValue(primary)
                .accessibilitySortPriority(55)
        }
        if let secondary = presentation.secondaryMetadata {
            Text(secondary)
                .font(skinFont(renderingAppearance.layoutPlan.typography.body, size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(CompactPlayerPresentation.metadataLineLimit)
                .truncationMode(.tail)
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
            .font(skinFont(renderingAppearance.layoutPlan.typography.label, size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceBackground(surface))
            .tint(surfaceTint(surface))
            .accessibilityValue(status.accessibilityValue)
            .accessibilityIdentifier("compact.status")
            .accessibilitySortPriority(50)
        } else if let emptyBody = presentation.emptyBody {
            Text(emptyBody)
                .font(skinFont(renderingAppearance.layoutPlan.typography.label, size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(emptyBody)
                .accessibilityLabel(emptyBody)
                .accessibilityValue(emptyBody)
                .accessibilityIdentifier("compact.status")
                .accessibilitySortPriority(50)
        }
        if needsNativeAppearanceRecovery || showsNativeAppearanceRecoveryStatus {
            Text("This appearance is unavailable. Native appearance has been restored.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(surfaceBackground(.criticalState))
                .tint(surfaceTint(.criticalState))
                .accessibilityIdentifier("compact.appearance-recovery")
                .accessibilityLabel("This appearance is unavailable. Native appearance has been restored.")
                .accessibilitySortPriority(45)
        }
    }

    @ViewBuilder
    private var transport: some View {
        let availability = presentation.transport
        let playPause = availability?.playPause ?? .play
        HStack(spacing: 8) {
            transportButton("Previous", systemImage: "backward.fill", enabled: availability?.previousEnabled == true, action: .previous)
            transportButton(playPause == .pause ? "Pause" : "Play Live", systemImage: playPause == .pause ? "pause.fill" : "play.fill", enabled: availability != nil, action: .playPause)
            transportButton("Next", systemImage: "forward.fill", enabled: availability?.nextEnabled == true, action: .next)
        }
        .frame(maxWidth: .infinity)
        .padding(CompactPlayerPresentation.focusClearance)
        .background(surfaceBackground(.transport))
        .tint(surfaceTint(.interactiveAccent))
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
            libraryButton
            Spacer()
            overflowMenu
        }
        .font(.system(size: 12))
        .padding(4)
        .background(surfaceBackground(.footer))
        .tint(surfaceTint(.interactiveAccent))
    }

    private var libraryButton: some View {
        Button { onAction(.showLibrary) } label: { Label("Show Library", systemImage: "rectangle.stack") }
            .help("Show Library")
            .accessibilityIdentifier("compact.show-library")
            .accessibilityLabel("Show Library")
            .accessibilitySortPriority(20)
    }

    private var overflowMenu: some View {
        Menu {
            Toggle("Always on Top", isOn: Binding(get: { isAlwaysOnTop }, set: { onAlwaysOnTopChanged($0) }))
                .accessibilityIdentifier("compact.always-on-top")
                .accessibilityLabel("Always on Top")
                .accessibilityValue(isAlwaysOnTop ? "On" : "Off")
                .accessibilitySortPriority(10)
            Divider()
            Button("Use Native Appearance") { onAppearanceRecovery() }
                .accessibilityIdentifier("compact.overflow.use-native-appearance")
                .accessibilityLabel("Use Native Appearance")
                .accessibilitySortPriority(9)
            Divider()
            Button("Sign Out") { onAction(.signOut) }.accessibilityIdentifier("compact.sign-out")
        } label: { Label("More", systemImage: "ellipsis.circle") }
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
            Text(presentation.emptyTitle ?? "Nothing Playing")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(presentation.emptyTitle ?? "Nothing Playing")
            if let emptyBody = presentation.emptyBody {
                Text(emptyBody)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(emptyBody)
                    .accessibilityLabel(emptyBody)
                    .accessibilityValue(emptyBody)
            }
            statusAndRecovery
            Button(presentation.emptyLibraryButtonTitle ?? "Show Library") { onAction(.showLibrary) }
                .accessibilityIdentifier("compact.show-library")
                .accessibilityLabel("Show Library")
                .frame(minWidth: CompactPlayerPresentation.transportControlSize, minHeight: CompactPlayerPresentation.transportControlSize)
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

    /// These treatments consume only validated colors. Their geometry, opacity,
    /// hit-testing, and accessibility behavior remain fixed and app-owned.
    private var appOwnedDecorativeSurfaces: some View {
        ZStack {
            RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                .stroke(surfaceTint(.chromeHighlight).opacity(0.72), lineWidth: 2)
                .padding(6)
            RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                .fill(surfaceTint(.displayGlow).opacity(0.24))
                .blur(radius: 18)
                .padding(20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var expressiveMaterialLayer: some View {
        let silhouette = renderingAppearance.layoutPlan.silhouette
        if silhouette != .nativeRect {
            Canvas { context, size in
                switch silhouette {
                case .pixelNotched:
                    let border = Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 0)
                    context.stroke(border, with: .color(surfaceTint(.chromeHighlight).opacity(0.72)), lineWidth: 2)
                    context.fill(Path(CGRect(x: 12, y: 28, width: size.width - 24, height: 8)), with: .color(surfaceTint(.displayGlow).opacity(0.38)))
                    for x in stride(from: 16, through: Int(size.width) - 16, by: 8) {
                        context.fill(Path(CGRect(x: x, y: 20, width: 2, height: 2)), with: .color(surfaceTint(.chromeHighlight).opacity(0.35)))
                    }
                case .discPod:
                    context.fill(
                        Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 36),
                        with: .color(surfaceTint(.displayGlow).opacity(0.36))
                    )
                    context.stroke(
                        Path(roundedRect: CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24), cornerRadius: 32),
                        with: .color(surfaceTint(.chromeHighlight).opacity(0.62)),
                        lineWidth: 2
                    )
                    context.fill(Path(ellipseIn: CGRect(x: 20, y: 164, width: 176, height: 92)), with: .color(surfaceTint(.metadata).opacity(0.32)))
                    for point in [CGPoint(x: 24, y: 24), CGPoint(x: size.width - 30, y: 24), CGPoint(x: 24, y: size.height - 30), CGPoint(x: size.width - 30, y: size.height - 30)] {
                        context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 6, height: 6)), with: .color(surfaceTint(.chromeHighlight).opacity(0.72)))
                    }
                    for x in stride(from: 132, through: 300, by: 12) {
                        context.fill(Path(CGRect(x: x, y: 72, width: 6, height: 3)), with: .color(surfaceTint(.interactiveAccent).opacity(0.5)))
                    }
                case .bubbleCapsule:
                    context.fill(Path(CGRect(x: 8, y: 8, width: size.width - 16, height: size.height * 0.45)), with: .color(surfaceTint(.displayGlow).opacity(0.38)))
                    context.fill(Path(CGRect(x: 8, y: size.height * 0.5, width: size.width - 16, height: size.height * 0.42)), with: .color(surfaceTint(.metadata).opacity(0.34)))
                    context.fill(Path(roundedRect: CGRect(x: 16, y: 36, width: size.width - 32, height: 112), cornerRadius: 24), with: .color(surfaceTint(.chromeHighlight).opacity(0.18)))
                    context.stroke(Path(roundedRect: CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24), cornerRadius: 40), with: .color(surfaceTint(.chromeHighlight).opacity(0.7)), lineWidth: 2)
                    for bubble in [CGRect(x: 32, y: 176, width: 12, height: 12), CGRect(x: 72, y: 204, width: 8, height: 8), CGRect(x: size.width - 64, y: 172, width: 16, height: 16), CGRect(x: size.width - 92, y: 204, width: 8, height: 8)] {
                        context.stroke(Path(ellipseIn: bubble), with: .color(surfaceTint(.chromeHighlight).opacity(0.58)), lineWidth: 1)
                    }
                case .nativeRect:
                    break
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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

private struct CompactSkinSilhouetteShape: Shape {
    let variant: CompactSkinSilhouetteVariant
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        switch variant {
        case .nativeRect:
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        case .pixelNotched:
            let notch: CGFloat = 8
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notch))
            path.closeSubpath()
            return path
        case .discPod:
            return Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: min(rect.width, rect.height) / 2)
        case .bubbleCapsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 3)
        }
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
